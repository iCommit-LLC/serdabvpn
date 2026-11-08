import Link from "next/link";

export default function DeviceNotFound() {
  return (
    <div className="card mt-6 space-y-3 p-5">
      <h2 className="font-serif text-2xl">No such device</h2>
      <p className="text-sm text-muted">It may have been revoked.</p>
      <Link href="/" className="btn-ghost">
        All devices
      </Link>
    </div>
  );
}
