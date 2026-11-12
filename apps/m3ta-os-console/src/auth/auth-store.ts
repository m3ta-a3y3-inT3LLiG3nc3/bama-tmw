import { mkdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import os from "node:os";
import path from "node:path";
type IngressOp = "run" | "connect";

/**
 * Sessions, users, thread owners, and one-time passes live in one SQLite file.
 *
 * `globalThis` is shared by route bundles in a single process and by nothing
 * else. Two Node processes each had their own Maps, so a logout in one left
 * the other accepting the token. This file is the store they share. Node's
 * built-in `node:sqlite` is already in the runtime, so this does not add a
 * hosted service. The default path is the console's existing local support
 * directory. Tests point `CONSOLE_AUTH_DB` at a temporary file.
 *
 * In-flight abort tickets stay in memory. An AbortSignal cannot be shared
 * with another process.
 */
let db: DatabaseSync | undefined;
let openedPath: string | undefined;

export function authDatabasePath(): string {
  const fromEnv = process.env.CONSOLE_AUTH_DB;
  if (fromEnv && fromEnv.trim().length > 0) return fromEnv;
  return path.join(os.homedir(), "Library", "Application Support", "M3taOS", "console-auth.sqlite");
}

function database(): DatabaseSync {
  const file = authDatabasePath();
  if (db && openedPath === file) return db;
  if (db) db.close();
  mkdirSync(path.dirname(file), { recursive: true });
  const next = new DatabaseSync(file);
  next.exec("PRAGMA journal_mode = WAL");
  next.exec("PRAGMA busy_timeout = 5000");
  next.exec(`
    CREATE TABLE IF NOT EXISTS users (
      user_id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      password_hash TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      revoked INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS threads (
      thread_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS permits (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      op TEXT NOT NULL
    );
  `);
  db = next;
  openedPath = file;
  return next;
}

type UserRow = { user_id: string; name: string; password_hash: string };
type SessionRow = { token: string; user_id: string; name: string; revoked: number };
type ThreadRow = { user_id: string };
type CountRow = { n: number };
type IdRow = { id: string };

export function resetDurableAuth(): void {
  database().exec("DELETE FROM permits; DELETE FROM sessions; DELETE FROM threads; DELETE FROM users;");
}

export function upsertUser(userId: string, name: string, passwordHashHex: string): void {
  database().prepare(`
    INSERT INTO users (user_id, name, password_hash) VALUES (?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET name = excluded.name, password_hash = excluded.password_hash
  `).run(userId, name, passwordHashHex);
}

export function findUser(userId: string): { userId: string; name: string; passwordHashHex: string } | null {
  const row = database().prepare("SELECT user_id, name, password_hash FROM users WHERE user_id = ?").get(userId) as UserRow | undefined;
  if (!row) return null;
  return { userId: row.user_id, name: row.name, passwordHashHex: row.password_hash };
}

export function userExists(userId: string): boolean {
  return findUser(userId) !== null;
}

export function userCount(): number {
  const row = database().prepare("SELECT COUNT(*) AS n FROM users").get() as CountRow;
  return row.n;
}

export function insertSession(token: string, userId: string, name: string): void {
  database().prepare("INSERT INTO sessions (token, user_id, name, revoked) VALUES (?, ?, ?, 0)").run(token, userId, name);
}

export function findSession(token: string): { token: string; userId: string; name: string; revoked: boolean } | null {
  const row = database().prepare("SELECT token, user_id, name, revoked FROM sessions WHERE token = ?").get(token) as SessionRow | undefined;
  if (!row) return null;
  return { token: row.token, userId: row.user_id, name: row.name, revoked: row.revoked !== 0 };
}

export function markSessionRevoked(token: string): boolean {
  const result = database().prepare("UPDATE sessions SET revoked = 1 WHERE token = ? AND revoked = 0").run(token);
  return result.changes === 1;
}

export function threadOwner(threadId: string): string | undefined {
  const row = database().prepare("SELECT user_id FROM threads WHERE thread_id = ?").get(threadId) as ThreadRow | undefined;
  return row?.user_id;
}

export function claimThreadRow(userId: string, threadId: string): "claimed" | "owned" | "foreign" {
  const inserted = database().prepare(
    "INSERT INTO threads (thread_id, user_id) VALUES (?, ?) ON CONFLICT(thread_id) DO NOTHING",
  ).run(threadId, userId);
  const owner = threadOwner(threadId);
  if (owner !== userId) return "foreign";
  return inserted.changes === 1 ? "claimed" : "owned";
}

export function insertPermit(permit: { id: string; userId: string; threadId: string; op: IngressOp }): void {
  database().prepare("INSERT INTO permits (id, user_id, thread_id, op) VALUES (?, ?, ?, ?)").run(
    permit.id,
    permit.userId,
    permit.threadId,
    permit.op,
  );
}

export function consumePermitRow(id: string, threadId: string, op: IngressOp): boolean {
  const row = database().prepare(
    "DELETE FROM permits WHERE id = ? AND thread_id = ? AND op = ? RETURNING id",
  ).get(id, threadId, op) as IdRow | undefined;
  return row !== undefined;
}
