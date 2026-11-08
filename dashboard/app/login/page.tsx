import { redirect } from "next/navigation";
import { Mark } from "@/components/Mark";
import { SerdabError, validateKey } from "@/lib/server/serdab";
import { getAdminKey, setAdminKey } from "@/lib/server/session";

/**
 * Login = paste the server's admin key (/etc/serdab/admin.key). It is checked
 * against GET /admin/v1/overview and kept in an httpOnly cookie.
 */
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  if (await getAdminKey()) redirect("/");
  const { error } = await searchParams;

  async function login(formData: FormData) {
    "use server";
    const key = String(formData.get("key") ?? "").trim();
    if (!key) redirect("/login?error=missing");
    let ok = false;
    try {
      ok = await validateKey(key);
    } catch (e) {
      if (e instanceof SerdabError) redirect("/login?error=unreachable");
      throw e;
    }
    if (!ok) redirect("/login?error=invalid");
    await setAdminKey(key);
    redirect("/");
  }

  const message =
    error === "invalid"
      ? "The server rejected that key."
      : error === "unreachable"
        ? "The server did not answer. Is serdabd running?"
        : error === "missing"
          ? "Paste the key."
          : null;

  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center text-center">
          <Mark size={64} />
          <h1 className="mt-4 font-serif text-4xl">Serdab</h1>
          <p className="mt-1 text-sm text-muted">Who is underground, and the way to close the door.</p>
        </div>
        <form action={login} className="card space-y-4 p-5">
          <label className="block">
            <span className="label">Admin key</span>
            <input
              type="password"
              name="key"
              autoFocus
              autoComplete="current-password"
              className="field mt-2 font-mono"
              placeholder="from /etc/serdab/admin.key"
            />
          </label>
          {message ? <p className="text-sm text-danger">{message}</p> : null}
          <button type="submit" className="btn-primary w-full">
            Open
          </button>
        </form>
      </div>
    </main>
  );
}
