import { notFound } from "next/navigation";
import { and, desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { attachments, notes } from "@/db/schema";
import { requireUser } from "@/lib/auth";
import { deleteNoteAction, updateNoteAction } from "@/app/actions";

export const dynamic = "force-dynamic";

export default async function EditNote({ params }: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await params;
  const [note] = await db.select().from(notes).where(and(eq(notes.id, id), eq(notes.userId, user.id))).limit(1);

  if (!note) {
    notFound();
  }

  const files = await db
    .select()
    .from(attachments)
    .where(and(eq(attachments.noteId, note.id), eq(attachments.userId, user.id)))
    .orderBy(desc(attachments.createdAt));
  const images = files.filter((file) => file.contentType.startsWith("image/"));
  const documents = files.filter((file) => !file.contentType.startsWith("image/"));

  return (
    <main className="editor-shell">
      <section className="editor-card">
        <form action={updateNoteAction} className="editor-form">
          <input type="hidden" name="noteId" value={note.id} />
          <label>Title<input name="title" defaultValue={note.title} required /></label>
          <label>Content<textarea name="content" rows={16} defaultValue={note.content} /></label>
          <div className="row-actions">
            <button className="button primary" type="submit">Save changes</button>
          </div>
        </form>

        <form action={deleteNoteAction}>
          <input type="hidden" name="noteId" value={note.id} />
          <button className="danger-button" type="submit">Delete note</button>
        </form>
      </section>

      <aside className="attachments-card">
        <h2>Images and files</h2>
        <form action="/api/upload" method="post" encType="multipart/form-data" className="upload-form">
          <input type="hidden" name="noteId" value={note.id} />
          <input name="file" type="file" accept="image/*,.pdf,.txt,.md,.csv,.doc,.docx" required />
          <button className="button secondary" type="submit">Save upload</button>
        </form>

        {files.length === 0 ? (
          <p className="muted">No uploads yet. Add images, screenshots, PDFs, or source files for this note.</p>
        ) : (
          <>
            {images.length > 0 && (
              <div className="image-grid">
                {images.map((image) => (
                  <a href={`/api/files/${image.id}`} className="image-tile" key={image.id}>
                    <img src={`/api/files/${image.id}`} alt={image.fileName} />
                    <span>{image.fileName}</span>
                  </a>
                ))}
              </div>
            )}
            {documents.length > 0 && (
              <div className="file-list">
                {documents.map((file) => (
                  <a href={`/api/files/${file.id}`} className="file-row" key={file.id}>
                    <span>{file.fileName}</span>
                    <small>{Math.ceil(file.size / 1024)} KB</small>
                  </a>
                ))}
              </div>
            )}
          </>
        )}
      </aside>
    </main>
  );
}
