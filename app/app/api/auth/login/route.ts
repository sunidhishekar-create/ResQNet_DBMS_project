import { NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { z } from "zod";
import { pool } from "@/lib/db";
import { COOKIE_NAME, cookieOptions, signToken } from "@/lib/auth";

const schema = z.object({
  email: z.string().trim().toLowerCase().email().max(255),
  password: z.string().min(1).max(72),
});

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "Email and password are required" }, { status: 400 });
  }
  const { email, password } = parsed.data;

  const { rows } = await pool.query(
    "SELECT user_id, full_name, password_hash, role FROM users WHERE email = $1",
    [email]
  );
  const u = rows[0];

  // Same message for "no such user" and "wrong password" so emails cannot be probed
  const ok = u ? await bcrypt.compare(password, u.password_hash) : false;
  if (!ok) {
    return NextResponse.json({ error: "Invalid email or password" }, { status: 401 });
  }

  const token = await signToken({ userId: u.user_id, name: u.full_name, role: u.role });
  const res = NextResponse.json({ user: { id: u.user_id, name: u.full_name, role: u.role } });
  res.cookies.set(COOKIE_NAME, token, cookieOptions);
  return res;
}