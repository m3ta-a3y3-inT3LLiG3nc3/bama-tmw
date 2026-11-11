import { EventEncoder } from "@ag-ui/encoder";
import {
  CopilotRuntime,
  createCopilotRuntimeHandler,
  InMemoryAgentRunner,
  type CopilotRuntimeHooks,
} from "@copilotkit/runtime/v2";
import { ConsoleAgent } from "./agent.ts";
import { forbidden, json, unauthorized } from "./http.ts";
import { claimThread, ownsThread, sessionFromRequest } from "./registry.ts";

export type IdentifiedUser = { id: string; name: string };
export type IdentifyUser = (request: Request) => Promise<IdentifiedUser>;

type RouteLike = { method: string; threadId?: string };

let runtime: CopilotRuntime | undefined;
let dispatch: ((request: Request) => Promise<Response>) | undefined;

async function threadIdFromBody(request: Request): Promise<string | null> {
  try {
    const body = (await request.clone().json()) as { threadId?: unknown };
    return typeof body.threadId === "string" && body.threadId.length > 0 ? body.threadId : null;
  } catch {
    return null;
  }
}

async function authorizeRoute(request: Request, route: RouteLike, identifyUser: IdentifyUser): Promise<void> {
  const user = await identifyUser(request);
  if (route.method === "threads/clear") throw forbidden();
  if ("threadId" in route && route.threadId) {
    if (!ownsThread(user.id, route.threadId)) throw forbidden();
    return;
  }
  if (route.method === "agent/run" || route.method === "agent/connect") {
    const threadId = await threadIdFromBody(request);
    if (!threadId) throw json({ error: "threadId is required" }, 400);
    if (claimThread(user.id, threadId) === "foreign") throw forbidden();
  }
}

function decorate(request: Request, response: Response, route: RouteLike): Promise<Response> {
  return decorateResponse(request, response, route);
}

async function decorateResponse(request: Request, response: Response, route: RouteLike): Promise<Response> {
  const headers = new Headers(response.headers);
  headers.set("cache-control", "no-store");
  const userId = request.headers.get("x-m3ta-user-id");
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
  const observable = active.runner.connect({ threadId });
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
      return { default: new ConsoleAgent(session.userId) };
    },
    runner: new InMemoryAgentRunner(),
    sseKeepAliveIntervalSeconds: 0,
  });
  const hooks: CopilotRuntimeHooks = {
    onRequest: async ({ request }) => {
      const user = await identifyUser(request);
      const headers = new Headers(request.headers);
      headers.delete("x-m3ta-user-id");
      headers.set("x-m3ta-user-id", user.id);
      return new Request(request, { headers });
    },
    onBeforeHandler: async ({ request, route }) => {
      await authorizeRoute(request, route, identifyUser);
    },
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
