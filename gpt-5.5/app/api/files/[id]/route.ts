import { NextResponse } from "next/server";
import { GetObjectCommand } from "@aws-sdk/client-s3";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { attachments } from "@/db/schema";
import { requireUser } from "@/lib/auth";
import { getUploadsBucket, s3Client } from "@/lib/s3";

export const runtime = "nodejs";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await params;
  const [file] = await db.select().from(attachments).where(and(eq(attachments.id, id), eq(attachments.userId, user.id))).limit(1);

  if (!file) {
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }

  const object = await s3Client.send(new GetObjectCommand({ Bucket: getUploadsBucket(), Key: file.s3Key }));
  const body = await object.Body?.transformToByteArray();

  if (!body) {
    return NextResponse.json({ error: "File body missing" }, { status: 404 });
  }

  return new NextResponse(Buffer.from(body), {
    headers: {
      "Content-Type": file.contentType,
      "Content-Disposition": `inline; filename="${file.fileName.replaceAll('"', '')}"`
    }
  });
}
