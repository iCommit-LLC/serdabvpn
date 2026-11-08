import type { Metadata } from "next";
import { Join } from "./Join";

export const metadata: Metadata = {
  title: "Serdab invitation",
  description: "Open this on the phone that will use Serdab.",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

/**
 * Public: chat apps only make http(s) links tappable, so an invitation travels
 * as https://<this host>/join#c=...&n=... . Everything after # stays in the
 * browser (it is never sent to this server); the page turns it back into the
 * serdab:// link the app opens.
 */
export default function JoinPage() {
  return <Join />;
}
