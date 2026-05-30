import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "crypto";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { notes, attachments } from "@/db/schema";
import { getSession } from "@/lib/auth";
import { uploadObject } from "@/lib/s3";

const MAX_BYTES = 10 * 1024 * 1024; // 10 MB

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;

  const [note] = await db
    .select()
    .from(notes)
    .where(and(eq(notes.id, id), eq(notes.userId, session.userId)))
    .limit(1);
  if (!note) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const formData = await req.formData();
  const file = formData.get("file");
  if (!file || typeof file === "string") {
    return NextResponse.json({ error: "No file provided" }, { status: 400 });
  }

  const blob = file as File;
  if (blob.size > MAX_BYTES) {
    return NextResponse.json(
      { error: "File too large (max 10 MB)" },
      { status: 413 }
    );
  }

  const arrayBuffer = await blob.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);
  const contentType = blob.type || "application/octet-stream";
  const safeName = blob.name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 200);
  const key = `users/${session.userId}/notes/${id}/${randomUUID()}-${safeName}`;

  await uploadObject(key, buffer, contentType);

  const [attachment] = await db
    .insert(attachments)
    .values({
      noteId: id,
      userId: session.userId,
      s3Key: key,
      fileName: blob.name.slice(0, 500),
      contentType,
      size: blob.size,
    })
    .returning();

  // Touch the note's updatedAt.
  await db
    .update(notes)
    .set({ updatedAt: new Date() })
    .where(eq(notes.id, id));

  return NextResponse.json({ attachment });
}
