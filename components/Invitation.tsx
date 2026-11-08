import QRCode from "qrcode";
import { headers } from "next/headers";
import { CopyButton } from "./CopyButton";

/** The tappable form of an invitation: chat apps do not linkify serdab:// links. */
async function joinUrl(link: string): Promise<string> {
  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "";
  const proto = h.get("x-forwarded-proto") ?? "https";
  return `${proto}://${host}/join#${link.split("?")[1] ?? ""}`;
}

/** QR + link for an invitation, rendered on the server as an inline SVG. */
export async function Invitation({ name, link }: { name: string; link: string }) {
  const join = await joinUrl(link);
  const svg = await QRCode.toString(link, {
    type: "svg",
    errorCorrectionLevel: "L",
    margin: 2,
    color: { dark: "#120f0cff", light: "#fffaf1ff" },
  });
  return (
    <div className="space-y-4">
      <div
        className="mx-auto w-full max-w-[320px] overflow-hidden rounded-2xl bg-[#fffaf1] p-2 [&>svg]:h-auto [&>svg]:w-full"
        role="img"
        aria-label={`Invitation QR code for ${name}`}
        dangerouslySetInnerHTML={{ __html: svg }}
      />
      <p className="text-center text-sm text-muted">
        Same room: in the Serdab app, <span className="text-text">Scan a QR code</span>. Far away: send the
        link below; they tap it and then <span className="text-text">Open in Serdab</span>.
      </p>
      <p className="rounded-xl border border-amber/40 bg-amber/10 px-4 py-3 text-sm text-amber">
        This holds {name}&apos;s private key. Send it to that one person, then delete the message.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <CopyButton text={join} />
      </div>
      <p className="break-all rounded-xl bg-inset p-3 font-mono text-[11px] leading-relaxed text-muted select-all">
        {join}
      </p>
    </div>
  );
}
