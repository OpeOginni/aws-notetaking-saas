import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { notes, attachments } from "@/db/schema";
import { getSession } from "@/lib/auth";
import { deleteObject } from "@/lib/s3";

async function loadOwnedNote(noteId: string, userId: string) {
  const [note] = await db
    .select()
    .from(notes)
    .where(and(eq(notes.id, noteId), eq(notes.userId, userId)))
    .limit(1);
  return note ?? null;
}

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const note = await loadOwnedNote(id, session.userId);
  if (!note) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const noteAttachments = await db
    .select()
    .from(attachments)
    .where(eq(attachments.noteId, id));

  return NextResponse.json({ note, attachments: noteAttachments });
}

const updateSchema = z.object({
  title: z.string().max(300).optional(),
  content: z.string().optional(),
});

export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const note = await loadOwnedNote(id, session.userId);
  if (!note) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request" }, { status: 400 });
  }
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid input" }, { status: 400 });
  }

  const [updated] = await db
    .update(notes)
    .set({
      title:
        parsed.data.title !== undefined
          ? parsed.data.title.trim() || "Untitled note"
          : note.title,
      content: parsed.data.content ?? note.content,
      updatedAt: new Date(),
    })
    .where(eq(notes.id, id))
    .returning();

  return NextResponse.json({ note: updated });
}

export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const note = await loadOwnedNote(id, session.userId);
  if (!note) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  // Best-effort cleanup of S3 objects for this note's attachments.
  const noteAttachments = await db
    .select()
    .from(attachments)
    .where(eq(attachments.noteId, id));
  await Promise.allSettled(
    noteAttachments.map((a) => deleteObject(a.s3Key))
  );

  await db.delete(notes).where(eq(notes.id, id));

  return NextResponse.json({ ok: true });
}
