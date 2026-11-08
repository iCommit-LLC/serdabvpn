import "server-only";
import { cookies } from "next/headers";

/**
 * Session = the serdabd admin key in an httpOnly cookie. The key never reaches
 * browser JavaScript; every serdabd call happens server-side with it attached.
 */
const COOKIE_NAME = "serdab_admin";

const COOKIE_OPTS = {
  httpOnly: true,
  sameSite: "strict" as const,
  // COOKIE_INSECURE=1 only for `npm run start` over plain http in local tests.
  secure: process.env.NODE_ENV === "production" && process.env.COOKIE_INSECURE !== "1",
  path: "/",
  // 30 days: the key itself is the long-lived credential.
  maxAge: 60 * 60 * 24 * 30,
};

export async function getAdminKey(): Promise<string | null> {
  const store = await cookies();
  return store.get(COOKIE_NAME)?.value ?? null;
}

export async function setAdminKey(key: string): Promise<void> {
  const store = await cookies();
  store.set(COOKIE_NAME, key, COOKIE_OPTS);
}

export async function clearAdminKey(): Promise<void> {
  const store = await cookies();
  store.delete(COOKIE_NAME);
}
