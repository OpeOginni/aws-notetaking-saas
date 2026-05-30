import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { createNoteAction, listUserNotes } from "@/app/actions";

export const dynamic = "force-dynamic";

export default async function Dashboard() {
  const user = await requireUser();
  const notes = await listUserNotes(user.id);

  return (
    <main className="dashboard">
      <section className="dashboard-head">
        <div>
          <p className="eyebrow">Private workspace</p>
          <h1>{user.name}&apos;s notes</h1>
          <p className="muted">Create notes, update them later, and attach source files or images.</p>
        </div>
        <div className="stat-card">
          <strong>{notes.length}</strong>
          <span>Total notes</span>
        </div>
      </section>

      <section className="workspace-grid">
        <form className="note-composer" action={createNoteAction}>
          <h2>New note</h2>
          <label>Title<input name="title" placeholder="Q2 launch planning" required /></label>
          <label>Content<textarea name="content" rows={8} placeholder="Write the first draft..." /></label>
          <button className="button primary" type="submit">Create note</button>
        </form>

        <div className="note-list">
          {notes.length === 0 ? (
            <div className="empty-state">
              <h2>No notes yet</h2>
              <p>Create your first note to test database persistence and editing.</p>
            </div>
          ) : (
            notes.map((note) => (
              <Link className="note-row" href={`/notes/${note.id}/edit`} key={note.id}>
                <span>{note.title}</span>
                <small>{note.updatedAt.toLocaleString()}</small>
              </Link>
            ))
          )}
        </div>
      </section>
    </main>
  );
}
