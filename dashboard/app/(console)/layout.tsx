import Link from "next/link";
import { redirect } from "next/navigation";
import { Mark } from "@/components/Mark";
import { getAdminKey } from "@/lib/server/session";

export const dynamic = "force-dynamic";

export default async function ConsoleLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  if (!(await getAdminKey())) redirect("/login");

  return (
    <div className="mx-auto min-h-screen w-full max-w-5xl px-4 pb-16">
      <header className="flex items-center justify-between gap-3 py-4">
        <Link href="/" className="flex min-w-0 items-center gap-2.5">
          <Mark size={30} />
          <span className="font-serif text-2xl leading-none">Serdab</span>
        </Link>
        <nav className="flex items-center gap-2">
          <Link href="/invite" className="btn-primary px-3">
            New invitation
          </Link>
          <form action="/logout" method="post">
            <button type="submit" className="btn px-2 text-muted hover:text-text" aria-label="Sign out">
              Sign out
            </button>
          </form>
        </nav>
      </header>
      {children}
    </div>
  );
}
