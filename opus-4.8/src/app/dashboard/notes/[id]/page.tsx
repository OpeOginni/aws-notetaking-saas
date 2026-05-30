import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { notes, attachments } from "@/db/schema";
import { getSession } from "@/lib/auth";
import { notFound, redirect } from "next/navigation";
import NoteEditor from "./note-editor";

export default async function NotePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");

  const { id } = await params;

  const [note] = await db
    .select()
    .from(notes)
    .where(and(eq(notes.id, id), eq(notes.userId, session.userId)))
    .limit(1);

  if (!note) notFound();

  const noteAttachments = await db
    .select()
    .from(attachments)
    .where(eq(attachments.noteId, id));

  return (
    <NoteEditor
      note={{
        id: note.id,
        title: note.title,
        content: note.content,
      }}
      initialAttachments={noteAttachments.map((a) => ({
        id: a.id,
        fileName: a.fileName,
        contentType: a.contentType,
        size: a.size,
      }))}
    />
  );
}
