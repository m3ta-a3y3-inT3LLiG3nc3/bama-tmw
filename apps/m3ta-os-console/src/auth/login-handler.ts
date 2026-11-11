import { json, unauthorized } from "./http.ts";
import { authenticate, createSession, revokeToken, sessionFromRequest } from "./registry.ts";

type LoginBody = { userId?: unknown; password?: unknown };

export async function POST(request: Request): Promise<Response> {
  let body: LoginBody;
  try {
    body = (await request.json()) as LoginBody;
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  if (typeof body.userId !== "string" || typeof body.password !== "string") {
    return json({ error: "Invalid request body" }, 400);
  }
  const user = authenticate(body.userId, body.password);
  if (!user) return unauthorized();
  const session = createSession(user.userId, user.name);
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
