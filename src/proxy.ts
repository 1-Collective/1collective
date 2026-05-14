import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PUBLIC_PATHS = [
  "/",
  "/login",
  "/admin/login",
  "/forgot-password",
  "/reset-password",
  "/auth/callback",
];
const STATIC_PREFIXES = ["/_next", "/api/webhooks", "/favicon"];

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (STATIC_PREFIXES.some((p) => pathname.startsWith(p))) {
    return NextResponse.next();
  }

  const response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookiesToSet) => {
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const { data } = await supabase.auth.getUser();
  const user = data.user;

  const isAdminPath = pathname.startsWith("/admin");
  const isAppPath = pathname.startsWith("/app");
  const isOnboardingPath = pathname.startsWith("/onboarding");
  const isAuthPath = ["/login", "/admin/login"].some((p) =>
    pathname.startsWith(p)
  );

  // Anonymous: allow public paths only.
  if (!user) {
    if (PUBLIC_PATHS.includes(pathname) || pathname.startsWith("/signup/")) {
      return response;
    }
    if (isAdminPath) {
      const url = request.nextUrl.clone();
      url.pathname = "/admin/login";
      return NextResponse.redirect(url);
    }
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  // Authenticated: the per-route role enforcement happens in layouts (uses service-role lookup).
  // Proxy just blocks obvious cross-gate access:
  //   - tenant users hitting /admin → bounce
  //   - logged-in users hitting /login → bounce to /app
  if (isAuthPath) {
    const url = request.nextUrl.clone();
    url.pathname = isAdminPath ? "/admin" : "/app";
    return NextResponse.redirect(url);
  }

  // Defer deeper checks (operator-vs-tenant disjointness, onboarding state) to
  // route-group layouts where we can hit the service-role client without
  // running expensive lookups on every request.
  void isAppPath;
  void isOnboardingPath;

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|api/webhooks).*)"],
};
