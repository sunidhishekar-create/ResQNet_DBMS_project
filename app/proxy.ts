import { NextRequest, NextResponse } from "next/server";
import { COOKIE_NAME, verifyToken } from "@/lib/auth";

// Routes that do not need a login
const PUBLIC_API = ["/api/health", "/api/auth/login", "/api/auth/register", "/api/auth/logout"];

/**
 * First gate: reject requests with no valid session before they reach a route.
 * (Next.js 16 renamed middleware.ts to proxy.ts.)
 * Role checks are done again inside each route handler with requireRole(),
 * because the proxy is only a coarse filter.
 */
export async function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;
  if (PUBLIC_API.includes(pathname)) return NextResponse.next();

  const token = req.cookies.get(COOKIE_NAME)?.value;
  const session = token ? await verifyToken(token) : null;
  if (session) return NextResponse.next();

  if (pathname.startsWith("/api/")) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }
  const loginUrl = new URL("/login", req.url);
  loginUrl.searchParams.set("next", pathname);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ["/api/:path*", "/dashboard/:path*"],
};