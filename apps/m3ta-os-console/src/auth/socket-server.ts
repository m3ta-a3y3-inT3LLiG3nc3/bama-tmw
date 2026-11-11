import { createServer, type IncomingMessage } from "node:http";
import type { Duplex } from "node:stream";
import { WebSocketServer, type WebSocket } from "ws";
import { handleRuntime } from "./runtime-handler.ts";
import { getAuthRegistry, ownsThread, sessionFromToken } from "./registry.ts";

/**
 * Authenticated socket for the runtime stream.
 *
 * Refusing every browser upgrade fails closed and also breaks the SDK, which
 * delivers a run as an AG-UI event stream. This path checks the session
 * first, then forwards that same stream.
 */
function rejectUpgrade(socket: Duplex, status: number, statusText: string): void {
  socket.write(`HTTP/1.1 ${status} ${statusText}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
  socket.destroy();
}

function tokenFromUpgrade(request: IncomingMessage, url: URL): string {
  const header = request.headers.authorization;
  if (typeof header === "string" && header.toLowerCase().startsWith("bearer ")) {
    return header.slice("bearer ".length).trim();
  }
  return url.searchParams.get("access_token") ?? "";
}

function onceMessage(ws: WebSocket): Promise<string> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("socket input timed out")), 5000);
    ws.once("message", (data) => {
      clearTimeout(timer);
      resolve(data.toString());
    });
    ws.once("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

async function pipeRun(ws: WebSocket, token: string, threadId: string): Promise<void> {
  let raw = "";
  try {
    raw = await onceMessage(ws);
  } catch {
    ws.close(1008);
    return;
  }
  let claimedThread = "";
  try {
    const input = JSON.parse(raw) as { threadId?: unknown };
    claimedThread = typeof input.threadId === "string" ? input.threadId : "";
  } catch {
    ws.close(1003);
    return;
  }
  if (!claimedThread || claimedThread !== threadId) {
    ws.close(1008);
    return;
  }
  const response = await handleRuntime(new Request("http://127.0.0.1/api/copilotkit/agent/default/run", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: raw,
  }));
  if (!response.ok || !response.body) {
    ws.close(1008);
    return;
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  try {
    while (ws.readyState === ws.OPEN) {
      const { done, value } = await reader.read();
      if (done) break;
      ws.send(decoder.decode(value, { stream: true }));
    }
  } finally {
    reader.releaseLock();
    if (ws.readyState === ws.OPEN) ws.close(1000);
  }
}

export type AuthSocketServer = {
  port: number;
  close: () => Promise<void>;
};

export function startAuthServer(host = "127.0.0.1"): Promise<AuthSocketServer> {
  const wss = new WebSocketServer({ noServer: true });
  const server = createServer((_request, response) => {
    response.writeHead(404, { "content-type": "text/plain", "cache-control": "no-store" });
    response.end("Not found");
  });
  server.on("upgrade", (request, socket, head) => {
    let url: URL;
    try {
      url = new URL(request.url ?? "/", `http://${host}`);
    } catch {
      rejectUpgrade(socket, 400, "Bad Request");
      return;
    }
    if (url.pathname !== "/api/copilotkit/socket") {
      rejectUpgrade(socket, 404, "Not Found");
      return;
    }
    const threadId = url.searchParams.get("threadId") ?? "";
    const session = sessionFromToken(tokenFromUpgrade(request, url));
    if (!session) {
      rejectUpgrade(socket, 401, "Unauthorized");
      return;
    }
    const owner = getAuthRegistry().threads.get(threadId);
    if (!threadId || (owner !== undefined && !ownsThread(session.userId, threadId))) {
      rejectUpgrade(socket, 403, "Forbidden");
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => {
      void pipeRun(ws, session.token, threadId).catch(() => {
        if (ws.readyState === ws.OPEN) ws.close(1011);
      });
    });
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, host, () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      resolve({
        port,
        close: () => new Promise((done, fail) => {
          wss.close();
          server.close((error) => (error ? fail(error) : done()));
        }),
      });
    });
  });
}
