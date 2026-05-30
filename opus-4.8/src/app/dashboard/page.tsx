import Link from "next/link";
import { desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { notes, attachments } from "@/db/schema";
import { getSession } from "@/lib/auth";
import { redirect } from "next/navigation";
import NewNoteButton from "./new-note-button";

function formatDate(d: Date) {
  return new Date(d).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default async function DashboardPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await db
    .select()
    .from(notes)
    .where(eq(notes.userId, session.userId))
    .orderBy(desc(notes.updatedAt));

  // Count attachments per note.
  const attachRows = await db
    .select({ noteId: attachments.noteId })
    .from(attachments)
    .where(eq(attachments.userId, session.userId));
  const counts = new Map<string, number>();
  for (const a of attachRows) {
    counts.set(a.noteId, (counts.get(a.noteId) ?? 0) + 1);
  }

  return (
    <div>
      <div className="dash-header">
        <h1>Your notes</h1>
        <NewNoteButton />
      </div>

      {rows.length === 0 ? (
        <div className="empty">
          <h2>No notes yet</h2>
          <p>Create your first note to get started.</p>
          <div style={{ marginTop: 20 }}>
            <NewNoteButton />
          </div>
        </div>
      ) : (
        <div className="notes-grid">
          {rows.map((note) => {
            const count = counts.get(note.id) ?? 0;
            return (
              <Link
                key={note.id}
                href={`/dashboard/notes/${note.id}`}
                className="note-card"
                style={{ textDecoration: "none" }}
              >
                <h3>{note.title}</h3>
                <p className="preview">
                  {note.content || "No content yet…"}
                </p>
                <div className="meta">
                  Updated {formatDate(note.updatedAt)}
                  {count > 0 && (
                    <span className="badge"> · 📎 {count}</span>
                  )}
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
