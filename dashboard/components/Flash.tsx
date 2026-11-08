/** One-line result banner driven by ?done= / ?error= after a server action. */
export function Flash({ done, error, messages }: { done?: string; error?: string; messages: Record<string, string> }) {
  if (error) {
    return (
      <p role="alert" className="rounded-xl border border-danger/50 bg-danger/10 px-4 py-3 text-sm text-danger">
        {error}
      </p>
    );
  }
  if (done && messages[done]) {
    return (
      <p role="status" className="rounded-xl border border-ok/40 bg-ok/10 px-4 py-3 text-sm text-ok">
        {messages[done]}
      </p>
    );
  }
  return null;
}
