import { NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { z } from "zod";
import { pool } from "@/lib/db";
import { COOKIE_NAME, cookieOptions, signToken } from "@/lib/auth";

const schema = z.object({
  full_name: z.string().trim().min(1, "Name is required").max(100),
  email: z.string().trim().toLowerCase().email("Invalid email").max(255),
  password: z.string().min(8, "Password must be at least 8 characters").max(72),
});

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues.map((i) => i.message).join("; ") },
      { status: 400 }
    );
  }
  const { full_name, email, password } = parsed.data;
  const passwordHash = await bcrypt.hash(password, 10);

  try {
    // Public sign-up always creates a REPORTER. Only an admin can promote users.
    const { rows } = await pool.query(
      `INSERT INTO users (full_name, email, password_hash, role)
       VALUES ($1, $2, $3, 'REPORTER')
       RETURNING user_id, full_name, role`,
      [full_name, email, passwordHash]
    );
    const u = rows[0];
    const token = await signToken({ userId: u.user_id, name: u.full_name, role: u.role });
    const res = NextResponse.json(
      { user: { id: u.user_id, name: u.full_name, role: u.role } },
      { status: 201 }
    );
    res.cookies.set(COOKIE_NAME, token, cookieOptions);
    return res;
  } catch (err: unknown) {
    // 23505 = unique_violation (duplicate email), enforced by the database
    if ((err as { code?: string }).code === "23505") {
      return NextResponse.json({ error: "Email already registered" }, { status: 409 });
    }
    // 23514 = check_violation (database-level validation)
    if ((err as { code?: string }).code === "23514") {
      return NextResponse.json({ error: "Data rejected by database rules" }, { status: 400 });
    }
    console.error(err);
    return NextResponse.json({ error: "Server error" }, { status: 500 });
  }
}