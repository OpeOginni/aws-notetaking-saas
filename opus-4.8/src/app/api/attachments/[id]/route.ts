import { NextRequest, NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { attachments } from "@/db/schema";
import { getSession } from "@/lib/auth";
import { deleteObject } from "@/lib/s3";

export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;

  const [attachment] = await db
    .select()
    .from(attachments)
    .where(and(eq(attachments.id, id), eq(attachments.userId, session.userId)))
    .limit(1);

  if (!attachment) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  await Promise.allSettled([deleteObject(attachment.s3Key)]);
  await db.delete(attachments).where(eq(attachments.id, id));

  return NextResponse.json({ ok: true });
}
