import { NextResponse } from "next/server";
import { PutObjectCommand } from "@aws-sdk/client-s3";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { attachments, notes } from "@/db/schema";
import { requireUser } from "@/lib/auth";
import { getUploadsBucket, s3Client } from "@/lib/s3";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const user = await requireUser();
  const formData = await request.formData();
  const noteId = formData.get("noteId");
  const file = formData.get("file");

  if (typeof noteId !== "string" || !(file instanceof File)) {
    return NextResponse.json({ error: "noteId and file are required" }, { status: 400 });
  }

  const [note] = await db.select({ id: notes.id }).from(notes).where(and(eq(notes.id, noteId), eq(notes.userId, user.id))).limit(1);
  if (!note) {
    return NextResponse.json({ error: "Note not found" }, { status: 404 });
  }

  if (file.size > 8 * 1024 * 1024) {
    return NextResponse.json({ error: "File must be 8 MB or smaller" }, { status: 413 });
  }

  const attachmentId = crypto.randomUUID();
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");
  const s3Key = `${user.id}/${noteId}/${attachmentId}-${safeName}`;
  const bytes = Buffer.from(await file.arrayBuffer());

  await s3Client.send(new PutObjectCommand({
    Bucket: getUploadsBucket(),
    Key: s3Key,
    Body: bytes,
    ContentType: file.type || "application/octet-stream"
  }));

  await db.insert(attachments).values({
    id: attachmentId,
    noteId,
    userId: user.id,
    s3Key,
    fileName: file.name,
    contentType: file.type || "application/octet-stream",
    size: file.size
  });

  const forwardedHost = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
  const forwardedProto = request.headers.get("x-forwarded-proto") ?? "http";
  const origin = process.env.APP_URL ?? (forwardedHost ? `${forwardedProto}://${forwardedHost}` : request.url);

  return NextResponse.redirect(new URL(`/notes/${noteId}/edit`, origin), { status: 303 });
}
