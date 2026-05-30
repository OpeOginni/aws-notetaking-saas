import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { notes } from "@/db/schema";
import { getSession } from "@/lib/auth";

export async function GET() {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rows = await db
    .select()
    .from(notes)
    .where(eq(notes.userId, session.userId))
    .orderBy(desc(notes.updatedAt));

  return NextResponse.json({ notes: rows });
}

const createSchema = z.object({
  title: z.string().max(300).optional(),
  content: z.string().optional(),
});

export async function POST(req: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown = {};
  try {
    body = await req.json();
  } catch {
    // allow empty body to create a blank note
  }
  const parsed = createSchema.safeParse(body);
  const data = parsed.success ? parsed.data : {};

  const [note] = await db
    .insert(notes)
    .values({
      userId: session.userId,
      title: data.title?.trim() || "Untitled note",
      content: data.content ?? "",
    })
    .returning();

  return NextResponse.json({ note });
}
