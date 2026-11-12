import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { cp, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, beforeEach, describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { BaseEvent } from "@ag-ui/client";
import { WebSocket } from "ws";
import { ɵGLOBAL_STORE } from "@copilotkit/runtime/v2";
import { GET as loginGet, POST as loginPost } from "../src/app/api/login/route.ts";
import { POST as logoutPost } from "../src/app/api/logout/route.ts";
import { GET as runtimeGet, POST as runtimePost, identifyUser } from "../src/app/api/copilotkit/[[...slug]]/route.ts";
import { startAuthServer, type AuthSocketServer } from "../src/auth/socket-server.ts";
import {
  defaultAgentWork,
  getAuthRegistry,
  registerUser,
  resetDurableAuth,
  setAgentWork,
  setDispatchBarrier,
  type AgentWork,
} from "../src/auth/registry.ts";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
process.env.CONSOLE_AUTH_DB = path.join(mkdtempSync(path.join(tmpdir(), "m3ta-auth-hardening-")), "auth.sqlite");
const SECRET = "ada-private-thread-body";
const AFTER_LOGOUT = "AFTER_LOGOUT_SECRET";

type FetchHandler = (request: Request) => Promise<Response>;

function resetState(): void {
  resetDurableAuth();
  const registry = getAuthRegistry();
  registry.tickets.clear();
  registry.agentWork = defaultAgentWork;
  registry.dispatchBarrier = Promise.resolve();
  ɵGLOBAL_STORE.clear();
}

function authHeaders(token: string, extra?: Record<string, string>): Headers {
  return new Headers({ authorization: `Bearer ${token}`, ...extra });
}

function loginRequest(userId: string, password: string): Request {
  return new Request("http://console.test/api/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ userId, password }),
  });
}

async function login(userId: string, password: string, post: FetchHandler = loginPost): Promise<string> {
  const response = await post(loginRequest(userId, password));
  assert.equal(response.status, 200, await response.clone().text());
  const body = (await response.json()) as { token: string };
  return body.token;
}

function runBody(threadId: string, text: string): Record<string, unknown> {
  return {
    threadId,
    runId: crypto.randomUUID(),
    state: {},
    messages: [{ id: crypto.randomUUID(), role: "user", content: text }],
    tools: [],
    context: [],
    forwardedProps: {},
  };
}

function runRequest(token: string, threadId: string, text: string): Request {
  return new Request("http://console.test/api/copilotkit/agent/default/run", {
    method: "POST",
    headers: authHeaders(token, { "content-type": "application/json", accept: "text/event-stream" }),
    body: JSON.stringify(runBody(threadId, text)),
  });
}

async function waitFor(label: string, predicate: () => boolean): Promise<void> {
  const started = Date.now();
  while (!predicate()) {
    if (Date.now() - started > 3000) throw new Error(`timed out waiting for ${label}`);
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

function parseSse(text: string): Array<{ type?: string; delta?: string }> {
  const events: Array<{ type?: string; delta?: string }> = [];
  for (const block of text.split("\n\n")) {
    const line = block.split("\n").find((entry) => entry.startsWith("data:"));
    if (!line) continue;
    const payload = line.slice("data:".length).trim();
    if (!payload || payload === "[DONE]") continue;
    events.push(JSON.parse(payload) as { type?: string; delta?: string });
  }
  return events;
}

async function loadSeparateBundles(): Promise<{
  loginGet: FetchHandler;
  loginPost: FetchHandler;
  logoutPost: FetchHandler;
  runtimeGet: FetchHandler;
  identifyUser: (request: Request) => Promise<{ id: string; name: string }>;
  registerUser: typeof registerUser;
  cleanup: () => Promise<void>;
}> {
  const directory = await mkdtemp(path.join(root, ".test-bundles-"));
  const bundleA = path.join(directory, "a");
  const bundleB = path.join(directory, "b");
  await cp(path.join(root, "src"), path.join(bundleA, "src"), { recursive: true });
  await cp(path.join(root, "src"), path.join(bundleB, "src"), { recursive: true });
  const login = await import(pathToFileURL(path.join(bundleA, "src/app/api/login/route.ts")).href);
  const logout = await import(pathToFileURL(path.join(bundleA, "src/app/api/logout/route.ts")).href);
  const runtime = await import(pathToFileURL(path.join(bundleB, "src/app/api/copilotkit/[[...slug]]/route.ts")).href);
  const registry = await import(pathToFileURL(path.join(bundleA, "src/auth/registry.ts")).href);
  return {
    loginGet: login.GET,
    loginPost: login.POST,
    logoutPost: logout.POST,
    runtimeGet: runtime.GET,
    identifyUser: runtime.identifyUser,
    registerUser: registry.registerUser,
    cleanup: () => rm(directory, { recursive: true, force: true }),
  };
}

function socketStatus(url: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const timer = setTimeout(() => {
      ws.terminate();
      reject(new Error("socket status timed out"));
    }, 3000);
    let settled = false;
    const finish = (status: number) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(status);
      ws.terminate();
    };
    ws.on("unexpected-response", (_request, response) => finish(response.statusCode ?? 0));
    ws.on("open", () => finish(101));
    ws.on("error", () => {
      // `unexpected-response` also emits error. The status handler settles the promise.
    });
  });
}

function collectSocketRun(url: string, input: Record<string, unknown>): Promise<string> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let text = "";
    const timer = setTimeout(() => {
      ws.terminate();
      reject(new Error(`socket stream timed out: ${text}`));
    }, 5000);
    ws.on("unexpected-response", (_request, response) => {
      clearTimeout(timer);
      reject(new Error(`socket refused with ${response.statusCode}`));
    });
    ws.on("open", () => ws.send(JSON.stringify(input)));
    ws.on("message", (data) => {
      text += data.toString();
    });
    ws.on("close", () => {
      clearTimeout(timer);
      resolve(text);
    });
    ws.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

describe("M3ta-OS Console Copilot auth", { concurrency: false }, () => {
  const bundleCleanups: Array<() => Promise<void>> = [];

  beforeEach(() => {
    resetState();
  });

  after(async () => {
    await Promise.all(bundleCleanups.map((cleanup) => cleanup()));
  });

  test("shares a session across separately bundled login and runtime routes", async () => {
    const bundled = await loadSeparateBundles();
    bundleCleanups.push(bundled.cleanup);
    bundled.registerUser("ada", "secret", "Ada");

    const token = await login("ada", "secret", bundled.loginPost);
    const info = await bundled.runtimeGet(new Request("http://console.test/api/copilotkit/info", {
      headers: authHeaders(token),
    }));
    assert.equal(info.status, 200, await info.clone().text());
    assert.equal(info.headers.get("x-m3ta-user-id"), "ada");
    const named = await bundled.identifyUser(new Request("http://console.test/api/copilotkit/info", {
      headers: authHeaders(token),
    }));
    assert.deepEqual(named, { id: "ada", name: "Ada" });

    const revoked = await bundled.logoutPost(new Request("http://console.test/api/logout", {
      method: "POST",
      headers: authHeaders(token),
    }));
    assert.equal(revoked.status, 200);

    const loginAgain = await bundled.loginGet(new Request("http://console.test/api/login", {
      headers: authHeaders(token),
    }));
    const runtimeAgain = await bundled.runtimeGet(new Request("http://console.test/api/copilotkit/info", {
      headers: authHeaders(token),
    }));
    assert.equal(loginAgain.status, 401);
    assert.equal(runtimeAgain.status, 401);
    const loginBody = await loginAgain.text();
    const runtimeBody = await runtimeAgain.text();
    assert.equal(loginBody.includes("secret"), false);
    assert.equal(runtimeBody.includes("Ada"), false);
  });

  test("refuses a foreign thread on read, run, replay, and subscribe", async () => {
    registerUser("ada", "a", "Ada");
    registerUser("bea", "b", "Bea");
    const ada = await login("ada", "a");
    const bea = await login("bea", "b");
    const threadId = "thread-ada-1";

    const created = await runtimePost(runRequest(ada, threadId, SECRET));
    assert.equal(created.status, 200, await created.clone().text());
    const createdBody = await created.text();
    assert.equal(createdBody.includes(SECRET), true);

    const read = await runtimeGet(new Request(`http://console.test/api/copilotkit/threads/${threadId}/messages`, {
      headers: authHeaders(bea),
    }));
    const replay = await runtimeGet(new Request(`http://console.test/api/copilotkit/threads/${threadId}/events`, {
      headers: authHeaders(bea),
    }));
    const subscribe = await runtimePost(new Request("http://console.test/api/copilotkit/threads/subscribe", {
      method: "POST",
      headers: authHeaders(bea, { "content-type": "application/json" }),
      body: JSON.stringify({ threadId }),
    }));
    const rerun = await runtimePost(runRequest(bea, threadId, "intrusion"));

    for (const response of [read, replay, subscribe, rerun]) {
      assert.equal(response.status, 403);
      const body = await response.text();
      assert.equal(body.includes(SECRET), false);
      assert.equal(body.includes("intrusion"), false);
    }

    const ownRead = await runtimeGet(new Request(`http://console.test/api/copilotkit/threads/${threadId}/messages`, {
      headers: authHeaders(ada),
    }));
    assert.equal(ownRead.status, 200);
    assert.equal((await ownRead.text()).includes(SECRET), true);

    const ownReplay = await runtimeGet(new Request(`http://console.test/api/copilotkit/threads/${threadId}/events`, {
      headers: authHeaders(ada),
    }));
    assert.equal(ownReplay.status, 200);
    assert.equal((await ownReplay.text()).includes(SECRET), true);

    const ownSubscribe = await runtimePost(new Request("http://console.test/api/copilotkit/threads/subscribe", {
      method: "POST",
      headers: authHeaders(ada, { "content-type": "application/json" }),
      body: JSON.stringify({ threadId }),
    }));
    assert.equal(ownSubscribe.status, 200);
    assert.equal((await ownSubscribe.text()).includes(SECRET), true);
  });

  test("aborts upstream work on logout, including a dispatch that has not started", async () => {
    registerUser("ada", "a", "Ada");
    const ada = await login("ada", "a");
    const writes: string[] = [];
    let signal: AbortSignal | undefined;
    const hanging: AgentWork = async (input, nextSignal, emit) => {
      signal = nextSignal;
      emit({ type: "RUN_STARTED", threadId: input.threadId, runId: input.runId } as BaseEvent);
      emit({ type: "TEXT_MESSAGE_START", messageId: "m-live", role: "assistant" } as BaseEvent);
      writes.push("started");
      emit({ type: "TEXT_MESSAGE_CONTENT", messageId: "m-live", delta: "started" } as BaseEvent);
      await new Promise<void>((resolve) => {
        if (nextSignal.aborted) {
          resolve();
          return;
        }
        nextSignal.addEventListener("abort", () => resolve(), { once: true });
      });
      if (nextSignal.aborted) return;
      writes.push(AFTER_LOGOUT);
      emit({ type: "TEXT_MESSAGE_CONTENT", messageId: "m-live", delta: AFTER_LOGOUT } as BaseEvent);
    };
    setAgentWork(hanging);

    const running = await runtimePost(runRequest(ada, "long-run", "keep going"));
    assert.equal(running.status, 200);
    const bodyPromise = running.text();
    await waitFor("upstream start", () => writes.includes("started"));
    const revoked = await logoutPost(new Request("http://console.test/api/logout", {
      method: "POST",
      headers: authHeaders(ada),
    }));
    assert.equal(revoked.status, 200);
    assert.equal(signal?.aborted, true);
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.deepEqual(writes, ["started"]);
    const body = await bodyPromise;
    assert.equal(body.includes(AFTER_LOGOUT), false);

    const adaAgain = await login("ada", "a");
    const stored = await runtimeGet(new Request("http://console.test/api/copilotkit/threads/long-run/messages", {
      headers: authHeaders(adaAgain),
    }));
    const replay = await runtimeGet(new Request("http://console.test/api/copilotkit/threads/long-run/events", {
      headers: authHeaders(adaAgain),
    }));
    assert.equal(stored.status, 200, await stored.clone().text());
    assert.equal((await stored.text()).includes(AFTER_LOGOUT), false);
    assert.equal(replay.status, 200, await replay.clone().text());
    assert.equal((await replay.text()).includes(AFTER_LOGOUT), false);

    registerUser("bea", "b", "Bea");
    const bea = await login("bea", "b");
    let calls = 0;
    let release: () => void = () => {};
    const barrier = new Promise<void>((resolve) => {
      release = resolve;
    });
    setDispatchBarrier(barrier);
    setAgentWork(async () => {
      calls += 1;
    });
    const queued = runtimePost(runRequest(bea, "pending-run", "queued"));
    await waitFor("pending dispatch", () => {
      for (const ticket of getAuthRegistry().tickets.values()) {
        if (ticket.threadId === "pending-run" && ticket.phase === "pending") return true;
      }
      return false;
    });
    assert.equal(calls, 0);
    const queuedLogout = await logoutPost(new Request("http://console.test/api/logout", {
      method: "POST",
      headers: authHeaders(bea),
    }));
    assert.equal(queuedLogout.status, 200);
    release();
    const queuedResponse = await queued;
    assert.equal(queuedResponse.status, 200, await queuedResponse.clone().text());
    await queuedResponse.text();
    assert.equal(calls, 0);
    const pending = [...getAuthRegistry().tickets.values()].find((ticket) => ticket.threadId === "pending-run");
    assert.equal(pending?.phase, "cancelled");
  });

  test("refuses anonymous and foreign sockets and streams a full SDK run when the session matches", async () => {
    registerUser("ada", "a", "Ada");
    registerUser("bea", "b", "Bea");
    const ada = await login("ada", "a");
    const bea = await login("bea", "b");
    const threadId = "sock-owned";
    const created = await runtimePost(runRequest(ada, threadId, SECRET));
    assert.equal(created.status, 200, await created.clone().text());
    await created.text();

    const server: AuthSocketServer = await startAuthServer();
    try {
      const base = `ws://127.0.0.1:${server.port}/api/copilotkit/socket`;
      assert.equal(await socketStatus(`${base}?threadId=${threadId}`), 401);
      assert.equal(await socketStatus(`${base}?threadId=${threadId}&access_token=not-a-session`), 401);
      assert.equal(await socketStatus(`${base}?threadId=${threadId}&access_token=${encodeURIComponent(bea)}`), 403);

      const liveThread = "sock-live";
      const input = runBody(liveThread, "hello socket");
      const streamed = await collectSocketRun(
        `${base}?threadId=${liveThread}&access_token=${encodeURIComponent(ada)}`,
        input,
      );
      assert.equal(streamed.includes("data: "), true);
      const events = parseSse(streamed);
      assert.equal(events[0]?.type, "RUN_STARTED");
      assert.equal(events.some((event) => event.type === "TEXT_MESSAGE_CONTENT" && event.delta === "hello socket"), true);
      assert.equal(events.at(-1)?.type, "RUN_FINISHED");
      assert.equal(streamed.includes(SECRET), false);
    } finally {
      await server.close();
    }
  });
});
