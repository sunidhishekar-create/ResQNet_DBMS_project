import { pool } from "@/lib/db";
import { requireRole } from "@/lib/auth";

// ADMIN only: demonstrates backend role-based authorization
export async function GET() {
  const auth = await requireRole("ADMIN");
  if (auth instanceof Response) return auth;

  const { rows } = await pool.query(
    "SELECT user_id, full_name, email, role, created_at FROM users ORDER BY user_id"
  );
  return Response.json({ users: rows });
}