"use client";

export default function ConsoleError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="card mt-6 space-y-3 p-5">
      <h2 className="font-serif text-2xl">The server did not answer</h2>
      <p className="text-sm text-muted">
        serdabd may be down, or the VM is unreachable from here. {error.digest ? `(ref ${error.digest})` : null}
      </p>
      <button type="button" onClick={reset} className="btn-ghost">
        Try again
      </button>
    </div>
  );
}
