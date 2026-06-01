import Link from "next/link";

export default function NotFound() {
  return (
    <div className="empty">
      <h2>Note not found</h2>
      <p>This note doesn&apos;t exist or you don&apos;t have access to it.</p>
      <div style={{ marginTop: 20 }}>
        <Link className="btn" href="/dashboard">
          Back to dashboard
        </Link>
      </div>
    </div>
  );
}
