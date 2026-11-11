import { json } from "./http.ts";

/** Hard cap for a login body. Admission uses Content-Length before any read. */
export const LOGIN_MAX_BYTES = 4096;

export function loginBodyDeadlineMs(): number {
  const raw = process.env.CONSOLE_LOGIN_BODY_DEADLINE_MS;
  if (raw === undefined || raw === "") return 2000;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return 2000;
  return parsed;
}

/**
 * Refuse a login before the body is read.
 * A too-large Content-Length or a non-JSON media type never reaches the reader.
 */
export function admitLoginRequest(request: Request, maxBytes = LOGIN_MAX_BYTES): Response | null {
  const type = (request.headers.get("content-type") ?? "").toLowerCase();
  if (!type.startsWith("application/json")) {
    return json({ error: "Unsupported media type", code: "unsupported_media_type" }, 415);
  }
  const lengthHeader = request.headers.get("content-length");
  if (lengthHeader !== null) {
    const length = lengthHeader.trim();
    if (!/^\d+$/.test(length) || Number(length) > maxBytes) {
      return json({ error: "Payload too large", code: "payload_too_large" }, 413);
    }
  }
  return null;
}

/**
 * Read a login body with a byte cap and a deadline.
 * The deadline is checked while bytes arrive, so a stalled client cannot hold the handler open.
 */
export async function readLoginJson(request: Request): Promise<{ ok: true; value: unknown } | { ok: false; response: Response }> {
  const admitted = admitLoginRequest(request);
  if (admitted) return { ok: false, response: admitted };
  const body = request.body;
  if (!body) return { ok: false, response: json({ error: "Invalid request body", code: "invalid_body" }, 400) };

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      const error = new Error("deadline");
      (error as Error & { code: string }).code = "body_deadline";
      reject(error);
    }, loginBodyDeadlineMs());
  });
  try {
    while (true) {
      const step = await Promise.race([reader.read(), deadline]);
      if (step.done) break;
      total += step.value.byteLength;
      if (total > LOGIN_MAX_BYTES) {
        await reader.cancel();
        return { ok: false, response: json({ error: "Payload too large", code: "payload_too_large" }, 413) };
      }
      chunks.push(step.value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    const code = error instanceof Error ? (error as Error & { code?: string }).code : undefined;
    if (code === "body_deadline") {
      return { ok: false, response: json({ error: "Body read deadline exceeded", code: "body_deadline" }, 408) };
    }
    return { ok: false, response: json({ error: "Invalid request body", code: "invalid_body" }, 400) };
  } finally {
    if (timer) clearTimeout(timer);
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return { ok: true, value: JSON.parse(new TextDecoder().decode(bytes)) as unknown };
  } catch {
    return { ok: false, response: json({ error: "Invalid request body", code: "invalid_body" }, 400) };
  }
}
