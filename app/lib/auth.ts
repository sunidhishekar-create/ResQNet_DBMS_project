import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";

export type Role = "ADMIN" | "DISPATCHER" | "REPORTER";

export type Session = {
  userId: number;
  name: string;
  role: Role;
};

export const COOKIE_NAME = "resqnet_session";
const MAX_AGE_SECONDS = 60 * 60 * 8; // 8 hours

function secretKey() {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error("JWT_SECRET is not set in .env.local");
  return new TextEncoder().encode(secret);
}

export async function signToken(session: Session): Promise<string> {
  return new SignJWT({ name: session.name, role: session.role })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(String(session.userId))
    .setIssuedAt()
    .setExpirationTime(`${MAX_AGE_SECONDS}s`)
    .sign(secretKey());
}

export async function verifyToken(token: string): Promise<Session | null> {
  try {
    const { payload } = await jwtVerify(token, secretKey(), { algorithms: ["HS256"] });
    const userId = Number(payload.sub);
    const role = payload.role as Role;
    if (!Number.isInteger(userId) || !["ADMIN", "DISPATCHER", "REPORTER"].includes(role)) {
      return null;
    }
    return { userId, name: String(payload.name ?? ""), role };
  } catch {
    return null;
  }
}

/** Cookie options shared by login, register and logout. */
export const cookieOptions = {
  httpOnly: true,
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/",
  maxAge: MAX_AGE_SECONDS,
};

/** Read the logged-in user from the cookie (use inside route handlers). */
export async function getSession(): Promise<Session | null> {
  const store = await cookies();
  const token = store.get(COOKIE_NAME)?.value;
  return token ? verifyToken(token) : null;
}

/**
 * Backend role guard for route handlers.
 * Returns the session, or a ready-made 401/403 Response to return immediately:
 *
 *   const auth = await requireRole("ADMIN", "DISPATCHER");
 *   if (auth instanceof Response) return auth;
 */
export async function requireRole(...allowed: Role[]): Promise<Session | Response> {
  const session = await getSession();
  if (!session) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }
  if (!allowed.includes(session.role)) {
    return Response.json({ error: "Forbidden: insufficient role" }, { status: 403 });
  }
  return session;
}