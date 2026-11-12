import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { BaseEvent, RunAgentInput } from "@ag-ui/client";
import {
  claimThreadRow,
  consumePermitRow,
  findSession,
  findUser,
  insertPermit,
  insertSession,
  markSessionRevoked,
  resetDurableAuth,
  threadOwner,
  upsertUser,
  userCount,
  userExists,
} from "./auth-store.ts";

/**
 * Process-local run state.
 *
 * Sessions, users, thread owners, and one-time passes are in the SQLite file
 * opened by auth-store.ts, so two processes see the same login and the same
 * revocation. Abort tickets stay here: an AbortSignal does not cross a
 * process boundary. `globalThis` still matters for route bundles inside one
 * process, which would otherwise each have their own ticket map.
 */
const REGISTRY_KEY = Symbol.for("m3ta.console.copilot.auth.v1");

export type Session = {
  token: string;
  userId: string;
  name: string;
  revoked: boolean;
};

export type DispatchPhase = "pending" | "dispatched" | "cancelled" | "finished";

export type DispatchTicket = {
  runId: string;
  threadId: string;
  userId: string;
  phase: DispatchPhase;
  signal: AbortSignal;
  abort: () => void;
};

export type AgentWork = (
  input: RunAgentInput,
  signal: AbortSignal,
  emit: (event: BaseEvent) => void,
) => Promise<void>;

export type IngressOp = "run" | "connect";

export type IngressPermit = {
  id: string;
  userId: string;
  threadId: string;
  op: IngressOp;
};

export type CredentialDecision =
  | { ok: true; userId: string; name: string }
  | { ok: false; status: 401; code: "unauthorized"; error: "Unauthorized" }
  | { ok: false; status: 503; code: "credentials_unconfigured"; error: "Credentials are not configured" };

export type AuthRegistry = {
  tickets: Map<string, DispatchTicket>;
  agentWork: AgentWork;
  dispatchBarrier: Promise<void>;
};

function lastUserText(input: RunAgentInput): string {
  for (let index = input.messages.length - 1; index >= 0; index -= 1) {
    const message = input.messages[index];
    if (message && message.role === "user" && typeof message.content === "string") return message.content;
  }
  return "";
}

export async function defaultAgentWork(
  input: RunAgentInput,
  signal: AbortSignal,
  emit: (event: BaseEvent) => void,
): Promise<void> {
  const messageId = `m-${input.runId}`;
  const text = lastUserText(input);
  emit({ type: "RUN_STARTED", threadId: input.threadId, runId: input.runId } as BaseEvent);
  if (signal.aborted) return;
  emit({ type: "TEXT_MESSAGE_START", messageId, role: "assistant" } as BaseEvent);
  emit({ type: "TEXT_MESSAGE_CONTENT", messageId, delta: text } as BaseEvent);
  emit({ type: "TEXT_MESSAGE_END", messageId } as BaseEvent);
  if (signal.aborted) return;
  emit({ type: "RUN_FINISHED", threadId: input.threadId, runId: input.runId } as BaseEvent);
}

function createRegistry(): AuthRegistry {
  return {
    tickets: new Map(),
    agentWork: defaultAgentWork,
    dispatchBarrier: Promise.resolve(),
  };
}

export { resetDurableAuth, threadOwner };

export function getAuthRegistry(): AuthRegistry {
  const root = globalThis as typeof globalThis & Record<symbol, AuthRegistry | undefined>;
  const existing = root[REGISTRY_KEY];
  if (existing) return existing;
  const created = createRegistry();
  root[REGISTRY_KEY] = created;
  return created;
}

function hashPassword(password: string): Buffer {
  return createHash("sha256").update(password).digest();
}

function passwordMatches(password: string, expected: Buffer): boolean {
  const actual = hashPassword(password);
  return timingSafeEqual(actual, expected);
}

export function registerUser(userId: string, password: string, name = userId): void {
  upsertUser(userId, name, hashPassword(password).toString("hex"));
}

/** Request-time only. A missing value does not throw at import. */
export function absorbEnvUsers(): void {
  const raw = process.env.CONSOLE_AUTH_USERS;
  if (!raw) return;
  for (const pair of raw.split(",")) {
    const splitAt = pair.indexOf(":");
    if (splitAt <= 0) continue;
    const userId = pair.slice(0, splitAt).trim();
    const password = pair.slice(splitAt + 1);
    if (!userId || !password) continue;
    if (!userExists(userId)) registerUser(userId, password, userId);
  }
}

export function createSession(userId: string, name: string): Session {
  const session: Session = {
    token: randomBytes(32).toString("base64url"),
    userId,
    name,
    revoked: false,
  };
  insertSession(session.token, session.userId, session.name);
  return session;
}

export function sessionFromToken(token: string): Session | null {
  if (!token) return null;
  const session = findSession(token);
  if (!session || session.revoked) return null;
  return session;
}

export function sessionFromRequest(request: Request): Session | null {
  const header = request.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  return sessionFromToken(header.slice("bearer ".length).trim());
}

export function revokeToken(token: string): boolean {
  const session = findSession(token);
  if (!session || session.revoked) return false;
  if (!markSessionRevoked(token)) return false;
  for (const ticket of getAuthRegistry().tickets.values()) {
    if (ticket.userId === session.userId && (ticket.phase === "pending" || ticket.phase === "dispatched")) {
      ticket.abort();
    }
  }
  return true;
}

export function ownsThread(userId: string, threadId: string): boolean {
  return threadOwner(threadId) === userId;
}

export function claimThread(userId: string, threadId: string): "claimed" | "owned" | "foreign" {
  return claimThreadRow(userId, threadId);
}

export function openDispatchTicket(userId: string, input: { threadId: string; runId: string }): DispatchTicket {
  const controller = new AbortController();
  const ticket: DispatchTicket = {
    runId: input.runId,
    threadId: input.threadId,
    userId,
    phase: "pending",
    signal: controller.signal,
    abort() {
      if (!controller.signal.aborted) controller.abort();
    },
  };
  getAuthRegistry().tickets.set(input.runId, ticket);
  return ticket;
}

/**
 * Credential check for one login attempt.
 * This never throws, and it is not called while the module is loading.
 * No configured user returns 503. A wrong password returns 401.
 */
export function authenticate(userId: string, password: string): CredentialDecision {
  absorbEnvUsers();
  if (userCount() === 0) {
    return { ok: false, status: 503, code: "credentials_unconfigured", error: "Credentials are not configured" };
  }
  const user = findUser(userId);
  if (!user || !passwordMatches(password, Buffer.from(user.passwordHashHex, "hex"))) {
    return { ok: false, status: 401, code: "unauthorized", error: "Unauthorized" };
  }
  return { ok: true, userId, name: user.name };
}

export function mintPermit(userId: string, threadId: string, op: IngressOp): string {
  const id = randomBytes(16).toString("hex");
  insertPermit({ id, userId, threadId, op });
  return id;
}

export class IngressRefusedError extends Error {
  constructor() {
    super("direct ingress refused");
    this.name = "IngressRefusedError";
  }
}

/** Single-use. A runner call without a matching permit is direct ingress and is refused. */
export function consumePermit(id: string, threadId: string, op: IngressOp): boolean {
  if (!id) return false;
  return consumePermitRow(id, threadId, op);
}

export function setAgentWork(work: AgentWork): void {
  getAuthRegistry().agentWork = work;
}

/** Holds every new run in the pending phase until it resolves. Logout aborts that phase. */
export function setDispatchBarrier(barrier: Promise<void>): void {
  getAuthRegistry().dispatchBarrier = barrier;
}
