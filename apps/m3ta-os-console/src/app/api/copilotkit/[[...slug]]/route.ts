import { createRuntimeHandler, type IdentifiedUser } from "../../../../auth/runtime-handler.ts";
import { unauthorized } from "../../../../auth/http.ts";
import { sessionFromRequest } from "../../../../auth/registry.ts";

/**
 * Names the caller from the server-side session.
 *
 * CopilotKit 1.79 only keeps `identifyUser` on an Intelligence runtime, and
 * that mode needs a cloud key. The SSE runtime drops the option, and even
 * when Intelligence is on, `identifyUser` does not reject a foreign thread
 * on every route. This function is still the naming step: hooks call it, and
 * thread ownership is enforced beside it.
 */
export async function identifyUser(request: Request): Promise<IdentifiedUser> {
  const session = sessionFromRequest(request);
  if (!session) throw unauthorized();
  return { id: session.userId, name: session.name };
}

const handler = createRuntimeHandler(identifyUser);

export const GET = handler;
export const POST = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
