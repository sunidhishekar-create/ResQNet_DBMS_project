import type { PoolClient } from "pg";
import { pool } from "@/lib/db";

/**
 * Run `fn` inside one database transaction.
 * It also tells PostgreSQL who is acting (app.user_id), so the audit
 * triggers can fill audit_log.changed_by. Any error rolls everything back.
 */
export async function withTransaction<T>(
  userId: number,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [String(userId)]);
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/** Parse a numeric route/body id; returns null when it is not a positive integer. */
export function parseId(value: string): number | null {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

/** Turn a database error into a clean HTTP response. */
export function errorResponse(err: unknown): Response {
  const e = err as { code?: string; message?: string };
  switch (e.code) {
    case "P0001": // RAISE EXCEPTION inside our PL/pgSQL functions: messages are user-readable
      return Response.json({ error: e.message }, { status: 409 });
    case "23514": // check_violation
      return Response.json({ error: "Rejected by database rules (check constraint)" }, { status: 400 });
    case "23503": // foreign_key_violation
      return Response.json({ error: "Referenced record does not exist" }, { status: 400 });
    case "23505": // unique_violation
      return Response.json({ error: "Duplicate record" }, { status: 409 });
    default:
      console.error(err);
      return Response.json({ error: "Server error" }, { status: 500 });
  }
}