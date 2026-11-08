import { Flash } from "@/components/Flash";
import { invite } from "../actions";

const ROLE_HELP: Record<string, string> = {
  family: "Never expires. Can share guest invitations from their app. Sites filtered and kept for you (their app says the connection is monitored, not by whom).",
  kid: "Never expires. Cannot share. Sites filtered and kept for you (their app says the connection is monitored, not by whom).",
  guest: "Ends 21 days from now; an unused invitation is removed after 48 h. 30 GB a month, 5 Mbps, filtered.",
};

export default async function InvitePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; name?: string; role?: string }>;
}) {
  const { error, name = "", role = "guest" } = await searchParams;

  return (
    <main className="mx-auto max-w-lg space-y-5">
      <div>
        <h1 className="font-serif text-3xl">New invitation</h1>
        <p className="mt-1 text-sm text-muted">One invitation is one phone. You get a QR code and a link to send.</p>
      </div>
      <Flash error={error} messages={{}} />
      <form action={invite} className="card space-y-5 p-5">
        <label className="block">
          <span className="label">Device name</span>
          <input
            name="name"
            required
            defaultValue={name}
            pattern="[a-z0-9][a-z0-9\-]{0,31}"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            className="field mt-2 font-mono"
            placeholder="son-phone"
          />
          <span className="mt-1 block text-xs text-muted">Lowercase letters, digits and dashes.</span>
        </label>
        <fieldset className="space-y-2">
          <legend className="label mb-2">Who is it for</legend>
          {(["family", "kid", "guest"] as const).map((r) => (
            <label
              key={r}
              className="flex cursor-pointer gap-3 rounded-xl border border-line p-3 has-[:checked]:border-sand has-[:checked]:bg-inset"
            >
              <input type="radio" name="role" value={r} defaultChecked={r === role} className="mt-1 accent-[var(--c-sand)]" />
              <span>
                <span className="block font-medium capitalize">{r}</span>
                <span className="block text-xs text-muted">{ROLE_HELP[r]}</span>
              </span>
            </label>
          ))}
        </fieldset>
        <button type="submit" className="btn-primary w-full">
          Create invitation
        </button>
      </form>
    </main>
  );
}
