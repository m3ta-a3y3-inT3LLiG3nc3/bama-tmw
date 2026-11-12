import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { POST as runtimePost } from "../src/app/api/copilotkit/[[...slug]]/route.ts";
import { POST as loginPost } from "../src/app/api/login/route.ts";
import { POST as logoutPost } from "../src/app/api/logout/route.ts";
import { registerUser } from "../src/auth/registry.ts";

const dbDirectory = mkdtempSync(path.join(tmpdir(), "m3ta-auth-shared-"));
process.env.CONSOLE_AUTH_DB = path.join(dbDirectory, "auth.sqlite");

const cli = fileURLToPath(new URL("./auth-proc-cli.ts", import.meta.url));
const root = path.resolve(path.dirname(cli), "..");

function proc(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["--experimental-strip-types", cli, ...args], {
      cwd: root,
      env: process.env,
    });
    let out = "";
    let err = "";
    child.stdout.on("data", (chunk: Buffer) => {
      out += chunk.toString();
    });
    child.stderr.on("data", (chunk: Buffer) => {
      err += chunk.toString();
    });
    child.on("close", (code) => {
      if (code !== 0) reject(new Error(`auth proc ${args.join(" ")} exited ${code}: ${err}`));
      else resolve(out.trim());
    });
  });
}

describe("shared auth store", { concurrency: false }, () => {
  test("a session minted in one process works in another, and revocation is visible there", async () => {
    const token = await proc(["mint"]);
    assert.equal(token.length > 10, true);
    assert.equal(await proc(["probe", token]), "200");
    assert.equal(await proc(["revoke", token]), "revoked");
    assert.equal(await proc(["probe", token]), "401");
  });

  test("a one-time run pass minted in one process is consumed in another", async () => {
    const permit = await proc(["mint-permit"]);
    assert.equal(await proc(["consume-permit", permit]), "yes");
    assert.equal(await proc(["consume-permit", permit]), "no");
  });

  test("the in-repo agent ingress fails closed without a valid session", async () => {
    registerUser("ada", "secret", "Ada");
    const body = JSON.stringify({
      threadId: "jarvis-thread",
      runId: crypto.randomUUID(),
      state: {},
      messages: [{ id: "m", role: "user", content: "secret-run" }],
      tools: [],
      context: [],
      forwardedProps: {},
    });
    const missing = await runtimePost(new Request("http://console.test/api/copilotkit/agent/default/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body,
    }));
    assert.equal(missing.status, 401);
    assert.equal((await missing.text()).includes("secret-run"), false);

    const forged = await runtimePost(new Request("http://console.test/api/copilotkit/agent/default/run", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer not-a-session" },
      body,
    }));
    assert.equal(forged.status, 401);

    const login = await loginPost(new Request("http://console.test/api/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ userId: "ada", password: "secret" }),
    }));
    assert.equal(login.status, 200, await login.clone().text());
    const token = ((await login.json()) as { token: string }).token;
    const revoked = await logoutPost(new Request("http://console.test/api/logout", {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
    }));
    assert.equal(revoked.status, 200);
    const after = await runtimePost(new Request("http://console.test/api/copilotkit/agent/default/run", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body,
    }));
    assert.equal(after.status, 401);
    assert.equal((await after.text()).includes("secret-run"), false);
  });
});
