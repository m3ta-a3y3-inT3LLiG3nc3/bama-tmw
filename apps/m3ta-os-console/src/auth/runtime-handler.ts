import { EventEncoder } from "@ag-ui/encoder";
import type { BaseEvent } from "@ag-ui/client";
import {
  CopilotRuntime,
  createCopilotRuntimeHandler,
  InMemoryAgentRunner,
  type AgentRunnerConnectRequest,
  type AgentRunnerRunRequest,
  type CopilotRuntimeHooks,
} from "@copilotkit/runtime/v2";
import { Observable, throwError } from "rxjs";
import { ConsoleAgent } from "./agent.ts";
import { forbidden, json, unauthorized } from "./http.ts";
import { claimThread, consumePermit, IngressRefusedError, mintPermit, ownsThread, sessionFromRequest } from "./registry.ts";

export type IdentifiedUser = { id: string; name: string };
export type IdentifyUser = (request: Request) => Promise<IdentifiedUser>;

type RouteLike = { method: string; threadId?: string };

class BoundedRunner extends InMemoryAgentRunner {
  override run(request: AgentRunnerRunRequest): Observable<BaseEvent> {
    const permitId = request.agent instanceof ConsoleAgent ? request.agent.permitId : "";
    if (!consumePermit(permitId, request.threadId, "run")) {
      return throwError(() => new IngressRefusedError());
    }
    return super.run(request);
  }

  override connect(request: AgentRunnerConnectRequest): Observable<BaseEvent> {
    const headers = request.headers ?? {};
    const permitId = headers["x-m3ta-ingress"] ?? "";
    if (!consumePermit(permitId, request.threadId, "connect")) {
      return throwError(() => new IngressRefusedError());
    }
    return super.connect(request);
  }
}

let runtime: CopilotRuntime | undefined;
let dispatch: ((request: Request) => Promise<Response>) | undefined;

function requestWithBody(request: Request, body: string, permitId: string): Request {
  const headers = new Headers(request.headers);
  headers.delete("content-length");
  headers.delete("x-m3ta-user-id");
  headers.set("x-m3ta-ingress", permitId);
  headers.set("content-type", request.headers.get("content-type") ?? "application/json");
  return new Request(request.url, {
    method: request.method,
    headers,
    body,
  });
}

async function authorizeRoute(request: Request, route: RouteLike, identifyUser: IdentifyUser): Promise<Request | void> {
  const user = await identifyUser(request);
  if (route.method === "threads/clear") throw forbidden();
  if ("threadId" in route && route.threadId) {
    if (!ownsThread(user.id, route.threadId)) throw forbidden();
    return;
  }
  if (route.method === "agent/run" || route.method === "agent/connect") {
    const text = await request.text();
    let threadId = "";
    try {
      const parsed = JSON.parse(text) as { threadId?: unknown };
      if (typeof parsed.threadId === "string") threadId = parsed.threadId;
    } catch {
      threadId = "";
    }
    if (!threadId) throw json({ error: "threadId is required" }, 400);
    if (claimThread(user.id, threadId) === "foreign") throw forbidden();
    const op = route.method === "agent/connect" ? "connect" : "run";
    return requestWithBody(request, text, mintPermit(user.id, threadId, op));
  }
}

function decorate(request: Request, response: Response, route: RouteLike): Promise<Response> {
  return decorateResponse(request, response, route);
}

async function decorateResponse(request: Request, response: Response, route: RouteLike): Promise<Response> {
  const headers = new Headers(response.headers);
  headers.set("cache-control", "no-store");
  const userId = sessionFromRequest(request)?.userId ?? request.headers.get("x-m3ta-user-id");
  if (userId) headers.set("x-m3ta-user-id", userId);
  if (route.method === "threads/list" && response.ok && userId) {
    const body = (await response.json()) as { threads?: Array<{ id: string }> };
    const threads = (body.threads ?? []).filter((thread) => ownsThread(userId, thread.id));
    return json({ ...body, threads }, response.status);
  }
  return new Response(response.body, { status: response.status, headers });
}

async function handleSubscribe(request: Request, identifyUser: IdentifyUser): Promise<Response> {
  const user = await identifyUser(request);
  let threadId = "";
  try {
    const body = (await request.json()) as { threadId?: unknown };
    if (typeof body.threadId === "string") threadId = body.threadId;
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  if (!threadId || !ownsThread(user.id, threadId)) return forbidden();
  const active = runtime;
  if (!active) return json({ error: "Runtime unavailable" }, 500);
  const encoder = new EventEncoder();
  const observable = active.runner.connect({
    threadId,
    headers: { "x-m3ta-ingress": mintPermit(user.id, threadId, "connect") },
  });
  let subscription: { unsubscribe: () => void } | undefined;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      subscription = observable.subscribe({
        next(event) {
          controller.enqueue(encoder.encodeBinary(event));
        },
        error() {
          controller.close();
        },
        complete() {
          controller.close();
        },
      });
    },
    cancel() {
      subscription?.unsubscribe();
    },
  });
  return new Response(stream, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-store",
      "x-m3ta-user-id": user.id,
    },
  });
}

export function createRuntimeHandler(identifyUser: IdentifyUser): (request: Request) => Promise<Response> {
  if (dispatch) return dispatch;
  runtime = new CopilotRuntime({
    agents: ({ request }) => {
      const session = sessionFromRequest(request);
      if (!session) throw unauthorized();
      return { default: new ConsoleAgent(session.userId, request.headers.get("x-m3ta-ingress") ?? "") };
    },
    runner: new BoundedRunner(),
    sseKeepAliveIntervalSeconds: 0,
  });
  const hooks: CopilotRuntimeHooks = {
    onRequest: async ({ request }) => {
      await identifyUser(request);
    },
    onBeforeHandler: async ({ request, route }) => authorizeRoute(request, route, identifyUser),
    onResponse: async ({ request, response, route }) => decorate(request, response, route),
  };
  const sdk = createCopilotRuntimeHandler({
    runtime,
    basePath: "/api/copilotkit",
    hooks,
  });
  dispatch = async (request) => {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/$/, "");
    if (request.method === "POST" && path.endsWith("/threads/subscribe")) {
      return handleSubscribe(request, identifyUser);
    }
    return sdk(request);
  };
  return dispatch;
}

export function handleRuntime(request: Request): Promise<Response> {
  if (!dispatch) throw new Error("Runtime handler has not been created");
  return dispatch(request);
}

export function getRuntime(): CopilotRuntime {
  if (!runtime) throw new Error("Runtime handler has not been created");
  return runtime;
}
