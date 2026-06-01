import Link from "next/link";
import { getSession } from "@/lib/auth";
import { redirect } from "next/navigation";

export default async function Home() {
  const session = await getSession();
  if (session) redirect("/dashboard");

  return (
    <div className="container">
      <nav className="nav" style={{ border: "none", background: "transparent" }}>
        <span className="brand">📝 NoteSaaS</span>
        <div className="spacer" />
        <Link className="btn secondary" href="/login">
          Log in
        </Link>
      </nav>

      <section className="hero">
        <h1>
          Capture every idea.
          <br />
          Keep it forever.
        </h1>
        <p>
          NoteSaaS is a fast, secure place for your notes and files. Write
          markdown-style notes, attach images and documents, and access them
          from anywhere.
        </p>
        <div className="cta">
          <Link className="btn" href="/signup">
            Get started free
          </Link>
          <Link className="btn secondary" href="/login">
            I have an account
          </Link>
        </div>
      </section>

      <section className="features">
        <div className="feature">
          <h3>✍️ Rich notes</h3>
          <p>
            Create, edit, and organize notes with a clean, distraction-free
            editor that autosaves your work.
          </p>
        </div>
        <div className="feature">
          <h3>📎 File uploads</h3>
          <p>
            Attach images and documents to any note. Files are stored securely
            in Amazon S3 and served privately.
          </p>
        </div>
        <div className="feature">
          <h3>🔒 Secure by default</h3>
          <p>
            Password-protected accounts with encrypted sessions. Your data is
            scoped to you and only you.
          </p>
        </div>
        <div className="feature">
          <h3>☁️ Cloud-native</h3>
          <p>
            Runs on AWS ECS Fargate with RDS PostgreSQL behind a load-balanced
            endpoint for high availability.
          </p>
        </div>
      </section>
    </div>
  );
}
