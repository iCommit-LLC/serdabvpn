import { clearAdminKey } from "@/lib/server/session";

/**
 * Drops the session cookie (also where a rejected key lands) and goes to login.
 * Relative Location: behind Cloud Run the request's own host is not the public one.
 */
export async function GET() {
  await clearAdminKey();
  return new Response(null, { status: 303, headers: { location: "/login" } });
}

export const POST = GET;
