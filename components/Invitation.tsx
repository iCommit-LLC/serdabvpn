import QRCode from "qrcode";
import { CopyButton } from "./CopyButton";

/** QR + link for an invitation, rendered on the server as an inline SVG. */
export async function Invitation({ name, link }: { name: string; link: string }) {
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
        In the Serdab app: <span className="text-text">Scan a QR code</span>, or send the link and they
        tap <span className="text-text">I was sent an invitation</span>.
      </p>
      <p className="rounded-xl border border-amber/40 bg-amber/10 px-4 py-3 text-sm text-amber">
        This holds {name}&apos;s private key. Send it to that one person, then delete the message.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <CopyButton text={link} />
      </div>
      <p className="break-all rounded-xl bg-inset p-3 font-mono text-[11px] leading-relaxed text-muted select-all">
        {link}
      </p>
    </div>
  );
}
