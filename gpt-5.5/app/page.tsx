import Link from "next/link";

export default function Home() {
  return (
    <main className="hero">
      <section className="hero-copy">
        <p className="eyebrow">Notes, receipts, sketches, one secure workspace</p>
        <h1>Capture client notes and supporting files without leaving your browser.</h1>
        <p>
          Fieldnotes Cloud is a production-style SaaS example with account sign-up, PostgreSQL persistence,
          S3-backed uploads, and an ECS deployment path.
        </p>
        <div className="hero-actions">
          <Link className="button primary" href="/signup">Create account</Link>
          <Link className="button secondary" href="/login">Log in</Link>
        </div>
      </section>
      <section className="product-card">
        <div className="card-header">
          <span>Today</span>
          <strong>12 notes</strong>
        </div>
        <article>
          <h2>Launch checklist</h2>
          <p>Attach architecture diagrams, capture meeting notes, and track updates in one place.</p>
        </article>
        <article>
          <h2>Customer interview</h2>
          <p>Keep transcripts, screenshots, and research files next to the decisions they informed.</p>
        </article>
      </section>
    </main>
  );
}
