"use client";

import { useState, useSyncExternalStore } from "react";
import { Mark } from "@/components/Mark";

type Lang = "en" | "fr" | "ar";
const T = {
  en: {
    title: (n: string) => (n ? `${n}, you are invited to Serdab` : "You are invited to Serdab"),
    sub: "Your own private tunnel. One tap sets this phone up.",
    open: "Open in Serdab",
    noApp: "Nothing happened? Install the Serdab app first, then come back to this page.",
    copy: "Or copy the invitation, open Serdab and tap “I was sent an invitation”.",
    copyBtn: "Copy the invitation",
    copied: "Copied",
    secret: "This link is a key for one phone. Do not forward it.",
    broken: "This invitation link is incomplete. Ask for a new one.",
  },
  fr: {
    title: (n: string) => (n ? `${n}, vous êtes invité·e sur Serdab` : "Vous êtes invité·e sur Serdab"),
    sub: "Votre tunnel privé. Un geste suffit pour configurer ce téléphone.",
    open: "Ouvrir dans Serdab",
    noApp: "Rien ne se passe ? Installez d'abord l'app Serdab, puis revenez sur cette page.",
    copy: "Ou copiez l'invitation, ouvrez Serdab et touchez « J'ai reçu une invitation ».",
    copyBtn: "Copier l'invitation",
    copied: "Copié",
    secret: "Ce lien est une clé pour un seul téléphone. Ne le transférez pas.",
    broken: "Ce lien d'invitation est incomplet. Demandez-en un nouveau.",
  },
  ar: {
    title: (n: string) => (n ? `${n}، أنت مدعو إلى سرداب` : "أنت مدعو إلى سرداب"),
    sub: "سردابك الخاص. لمسة واحدة تجهّز هذا الهاتف.",
    open: "افتح في سرداب",
    noApp: "لم يحدث شيء؟ ثبّت تطبيق سرداب أولاً ثم عد إلى هذه الصفحة.",
    copy: "أو انسخ الدعوة، افتح سرداب واضغط «وصلتني دعوة».",
    copyBtn: "انسخ الدعوة",
    copied: "تم النسخ",
    secret: "هذا الرابط مفتاح لهاتف واحد. لا تعِد إرساله.",
    broken: "رابط الدعوة ناقص. اطلب رابطًا جديدًا.",
  },
} as const;

const noop = () => () => {};

/** Reads the browser-only bits (the # part and the language) without an effect. */
function useBrowser<T>(read: () => T, server: T): T {
  return useSyncExternalStore(noop, read, () => server);
}

function parse(hash: string): { link: string | null; name: string } {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const c = params.get("c");
  const n = params.get("n") ?? "";
  const name = n.replace(/-/g, " ").replace(/\b\w/g, (m) => m.toUpperCase());
  const link = c && /^[A-Za-z0-9_-]+$/.test(c) ? `serdab://add?c=${c}${n ? `&n=${encodeURIComponent(n)}` : ""}` : null;
  return { link, name };
}

export function Join() {
  const hash = useBrowser(() => window.location.hash, "");
  const lang = useBrowser<Lang>(() => {
    const l = (navigator.language || "en").slice(0, 2);
    return l === "fr" || l === "ar" ? l : "en";
  }, "en");
  const ready = useBrowser(() => true, false);
  const { link, name } = parse(hash);
  const [copied, setCopied] = useState(false);

  const t = T[lang];
  return (
    <main dir={lang === "ar" ? "rtl" : "ltr"} className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-6 px-6 py-12 text-center">
      <Mark size={96} />
      {!ready ? null : link ? (
        <>
          <div className="space-y-2">
            <h1 className="font-serif text-4xl leading-tight">{t.title(name)}</h1>
            <p className="text-muted">{t.sub}</p>
          </div>
          <a href={link} className="btn-primary w-full py-4 text-lg">
            {t.open}
          </a>
          <p className="text-sm text-muted">{t.noApp}</p>
          <div className="w-full space-y-2 rounded-2xl border border-line p-4">
            <p className="text-sm text-muted">{t.copy}</p>
            <button
              type="button"
              className="btn-ghost w-full"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(link);
                  setCopied(true);
                  setTimeout(() => setCopied(false), 2000);
                } catch {
                  /* the button below the link still works */
                }
              }}
            >
              {copied ? t.copied : t.copyBtn}
            </button>
          </div>
          <p className="text-xs text-amber">{t.secret}</p>
        </>
      ) : (
        <p className="text-muted">{t.broken}</p>
      )}
    </main>
  );
}
