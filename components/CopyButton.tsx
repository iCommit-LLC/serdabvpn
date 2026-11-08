"use client";

import { useState } from "react";

/** The only client component: copying needs the browser clipboard. */
export function CopyButton({ text, label = "Copy link" }: { text: string; label?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className="btn-ghost"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          setCopied(true);
          setTimeout(() => setCopied(false), 2000);
        } catch {
          /* clipboard blocked: the link is selectable on the page */
        }
      }}
    >
      {copied ? "Copied" : label}
    </button>
  );
}
