import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";
import type { BaseEvent, RunAgentInput } from "@ag-ui/client";
import { ɵGLOBAL_STORE } from "@copilotkit/runtime/v2";
import { POST as loginPost } from "../src/app/api/login/route.ts";
import { POST as runtimePost } from "../src/app/api/copilotkit/[[...slug]]/route.ts";
import { ConsoleAgent } from "../src/auth/agent.ts";
import {
  defaultAgentWork,
  getAuthRegistry,
  registerUser,
  setAgentWork,
} from "../src/auth/registry.ts";
import { getRuntime } from "../src/auth/runtime-handler.ts";

const SECRET = "direct-ingress-secret";

function resetState(): void {
  const registry = getAuthRegistry();
  registry.sessions.clear();
  registry.users.clear();
  registry.threads.clear();
  registry.tickets.clear();
  (registry as { permits?: { clear: () => void } }).permits?.clear();
  registry.agentWork = defaultAgentWork;
  registry.dispatchBarrier = Promise.resolve();
  delete process.env.CONSOLE_AUTH_USERS;
  delete process.env.CONSOLE_LOGIN_BODY_DEADLINE_MS;
  ɵGLOBAL_STORE.clear();
}

function loginBody(userId: string, password: string): string {
  return JSON.stringify({ userId, password });
}

function runInput(threadId: string, text: string): RunAgentInput {
  return {
    threadId,
    runId: crypto.randomUUID(),
    state: {},
    messages: [{ id: crypto.randomUUID(), role: "user", content: text }],
    tools: [],
    context: [],
    forwardedProps: {},
  } as RunAgentInput;
}

describe("console auth follow-ups", { concurrency: false }, () => {
  beforeEach(() => {
    resetState();
  });

  test("login admits the request before reading an oversized body", async () => {
    const body = new ReadableStream({
      pull() {
        return new Promise(() => {});
      },
    });
    const response = await Promise.race([
      loginPost(new Request("http://console.test/api/login", {
        method: "POST",
        headers: { "content-type": "application/json", "content-length": "1000000" },
        body,
        duplex: "half",
      } as RequestInit & { duplex: "half" })),
      new Promise<Response>((resolve) => setTimeout(() => resolve(new Response("hung", { status: 599 })), 400)),
    ]);
    assert.equal(response.status, 413);
    const payload = await response.json() as { code?: string };
    assert.equal(payload.code, "payload_too_large");
  });

  test("login refuses a non-json content type before trusting the body", async () => {
    const response = await loginPost(new Request("http://console.test/api/login", {
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: loginBody("ada", "secret"),
    }));
    assert.equal(response.status, 415);
    const payload = await response.json() as { code?: string };
    assert.equal(payload.code, "unsupported_media_type");
  });

  test("login stops reading when the body misses the deadline", async () => {
    process.env.CONSOLE_LOGIN_BODY_DEADLINE_MS = "40";
    const body = new ReadableStream({
      pull() {
        return new Promise(() => {});
      },
    });
    const response = await Promise.race([
      loginPost(new Request("http://console.test/api/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body,
        duplex: "half",
      } as RequestInit & { duplex: "half" })),
      new Promise<Response>((resolve) => setTimeout(() => resolve(new Response("hung", { status: 599 })), 500)),
    ]);
    assert.equal(response.status, 408);
    const payload = await response.json() as { code?: string };
    assert.equal(payload.code, "body_deadline");
  });

  test("a small login still succeeds after admission", async () => {
    registerUser("ada", "secret", "Ada");
    const response = await loginPost(new Request("http://console.test/api/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: loginBody("ada", "secret"),
    }));
    assert.equal(response.status, 200, await response.clone().text());
    const payload = await response.json() as { token?: string; userId?: string };
    assert.equal(payload.userId, "ada");
    assert.equal(typeof payload.token, "string");
  });

  test("missing credentials are a typed response, not an import-time throw", async () => {
    const response = await loginPost(new Request("http://console.test/api/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: loginBody("ada", "secret"),
    }));
    assert.equal(response.status, 503);
    const payload = await response.json() as { code?: string; error?: string };
    assert.equal(payload.code, "credentials_unconfigured");
    assert.equal(typeof payload.error, "string");

    registerUser("ada", "secret", "Ada");
    const rejected = await loginPost(new Request("http://console.test/api/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: loginBody("ada", "nope"),
    }));
    assert.equal(rejected.status, 401);
    const denied = await rejected.json() as { code?: string };
    assert.equal(denied.code, "unauthorized");
  });

  test("a direct runner call cannot run or replay a thread without an ingress permit", async () => {
    registerUser("ada", "secret", "Ada");
    const login = await loginPost(new Request("http://console.test/api/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: loginBody("ada", "secret"),
    }));
    assert.equal(login.status, 200, await login.clone().text());
    const token = ((await login.json()) as { token: string }).token;
    const created = await runtimePost(new Request("http://console.test/api/copilotkit/agent/default/run", {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json", accept: "text/event-stream" },
      body: JSON.stringify(runInput("owned-thread", SECRET)),
    }));
    assert.equal(created.status, 200, await created.clone().text());
    assert.equal((await created.text()).includes(SECRET), true);

    let calls = 0;
    setAgentWork(async () => {
      calls += 1;
    });
    const directEvents: BaseEvent[] = [];
    const directError = await new Promise<unknown>((resolve) => {
      getRuntime().runner.run({
        threadId: "owned-thread",
        agent: new ConsoleAgent("ada"),
        input: runInput("owned-thread", "intrusion"),
      }).subscribe({
        next: (event) => directEvents.push(event),
        error: (error) => resolve(error),
        complete: () => resolve(null),
      });
    });
    assert.equal(calls, 0);
    assert.ok(directError instanceof Error);
    assert.equal(JSON.stringify(directEvents).includes("intrusion"), false);
    assert.equal(JSON.stringify(directEvents).includes(SECRET), false);

    const replay: BaseEvent[] = [];
    const replayError = await new Promise<unknown>((resolve) => {
      getRuntime().runner.connect({ threadId: "owned-thread" }).subscribe({
        next: (event) => replay.push(event),
        error: (error) => resolve(error),
        complete: () => resolve(null),
      });
    });
    assert.ok(replayError instanceof Error);
    assert.equal(JSON.stringify(replay).includes(SECRET), false);
  });
});
