export function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

export function unauthorized(): Response {
  return json({ error: "Unauthorized" }, 401);
}

export function forbidden(): Response {
  return json({ error: "Forbidden" }, 403);
}
