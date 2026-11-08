"use client";

import type { ReactNode } from "react";

/**
 * A form whose switches and pickers save the moment they change: a switch
 * that only applies after a button further down reads as broken. Typed fields
 * (numbers, dates) still wait for the submit button.
 */
export function AutoSaveForm({
  action,
  className,
  children,
}: {
  action: (formData: FormData) => Promise<void>;
  className?: string;
  children: ReactNode;
}) {
  return (
    <form
      action={action}
      className={className}
      onChange={(e) => {
        const t = e.target as unknown as HTMLInputElement | HTMLSelectElement;
        if (t.type === "checkbox" || t.tagName === "SELECT") e.currentTarget.requestSubmit();
      }}
    >
      {children}
    </form>
  );
}
