import { json, unauthorized } from "./http.ts";
import { readLoginJson } from "./login-body.ts";
import { authenticate, createSession, revokeToken, sessionFromRequest } from "./registry.ts";

type LoginBody = { userId?: unknown; password?: unknown };

export async function POST(request: Request): Promise<Response> {
  const read = await readLoginJson(request);
  if (!read.ok) return read.response;
  const body = read.value as LoginBody;
  if (typeof body.userId !== "string" || typeof body.password !== "string") {
    return json({ error: "Invalid request body", code: "invalid_body" }, 400);
  }
  const decision = authenticate(body.userId, body.password);
  if (!decision.ok) return json({ error: decision.error, code: decision.code }, decision.status);
  const session = createSession(decision.userId, decision.name);
  return json({ token: session.token, userId: session.userId, name: session.name }, 200);
}

export async function GET(request: Request): Promise<Response> {
  const session = sessionFromRequest(request);
  if (!session) return unauthorized();
  return json({ userId: session.userId, name: session.name }, 200);
}

export async function logout(request: Request): Promise<Response> {
  const session = sessionFromRequest(request);
  if (!session) return unauthorized();
  revokeToken(session.token);
  return json({ revoked: true }, 200);
}
