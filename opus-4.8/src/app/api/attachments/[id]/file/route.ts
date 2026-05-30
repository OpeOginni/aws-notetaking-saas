import { NextRequest, NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { attachments } from "@/db/schema";
import { getSession } from "@/lib/auth";
import { getObjectStream } from "@/lib/s3";

// Streams a private S3 object to its owner. Files are never publicly exposed;
// access is gated by the user's session and ownership check.
export async function GET(
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

  try {
    const obj = await getObjectStream(attachment.s3Key);
    const body = obj.Body as ReadableStream | null;
    if (!body) {
      return NextResponse.json({ error: "Empty object" }, { status: 404 });
    }
    return new NextResponse(body as unknown as BodyInit, {
      headers: {
        "Content-Type": attachment.contentType,
        "Content-Disposition": `inline; filename="${encodeURIComponent(
          attachment.fileName
        )}"`,
        "Cache-Control": "private, max-age=3600",
      },
    });
  } catch {
    return NextResponse.json(
      { error: "Failed to load file" },
      { status: 500 }
    );
  }
}
