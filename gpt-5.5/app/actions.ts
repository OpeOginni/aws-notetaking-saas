"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import bcrypt from "bcryptjs";
import { and, desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { notes, sessions, users } from "@/db/schema";
import { clearSessionCookie, requireUser, setSessionCookie, SESSION_COOKIE } from "@/lib/auth";
import { cookies } from "next/headers";

function field(formData: FormData, name: string) {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim() : "";
}

function id() {
  return crypto.randomUUID();
}

export async function signUpAction(formData: FormData) {
  const name = field(formData, "name");
  const email = field(formData, "email").toLowerCase();
  const password = field(formData, "password");

  if (!name || !email || password.length < 8) {
    redirect("/signup?error=Use a name, valid email, and password with at least 8 characters");
  }

  const existing = await db.select({ id: users.id }).from(users).where(eq(users.email, email)).limit(1);
  if (existing.length > 0) {
    redirect("/signup?error=An account already exists for that email");
  }

  const userId = id();
  const passwordHash = await bcrypt.hash(password, 12);
  await db.insert(users).values({ id: userId, name, email, passwordHash });

  const sessionId = id();
  await db.insert(sessions).values({
    id: sessionId,
    userId,
    expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30)
  });
  await setSessionCookie(sessionId);
  redirect("/dashboard");
}

export async function loginAction(formData: FormData) {
  const email = field(formData, "email").toLowerCase();
  const password = field(formData, "password");

  const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);
  const valid = user ? await bcrypt.compare(password, user.passwordHash) : false;

  if (!valid || !user) {
    redirect("/login?error=Invalid email or password");
  }

  const sessionId = id();
  await db.insert(sessions).values({
    id: sessionId,
    userId: user.id,
    expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30)
  });
  await setSessionCookie(sessionId);
  redirect("/dashboard");
}

export async function logoutAction() {
  const cookieStore = await cookies();
  const sessionId = cookieStore.get(SESSION_COOKIE)?.value;
  if (sessionId) {
    await db.delete(sessions).where(eq(sessions.id, sessionId));
  }
  await clearSessionCookie();
  redirect("/");
}

export async function createNoteAction(formData: FormData) {
  const user = await requireUser();
  const title = field(formData, "title") || "Untitled note";
  const content = field(formData, "content");
  const noteId = id();

  await db.insert(notes).values({ id: noteId, userId: user.id, title, content });
  revalidatePath("/dashboard");
  redirect(`/notes/${noteId}/edit`);
}

export async function updateNoteAction(formData: FormData) {
  const user = await requireUser();
  const noteId = field(formData, "noteId");
  const title = field(formData, "title") || "Untitled note";
  const content = field(formData, "content");

  await db
    .update(notes)
    .set({ title, content, updatedAt: new Date() })
    .where(and(eq(notes.id, noteId), eq(notes.userId, user.id)));

  revalidatePath("/dashboard");
  revalidatePath(`/notes/${noteId}/edit`);
}

export async function deleteNoteAction(formData: FormData) {
  const user = await requireUser();
  const noteId = field(formData, "noteId");
  await db.delete(notes).where(and(eq(notes.id, noteId), eq(notes.userId, user.id)));
  revalidatePath("/dashboard");
  redirect("/dashboard");
}

export async function listUserNotes(userId: string) {
  return db.select().from(notes).where(eq(notes.userId, userId)).orderBy(desc(notes.updatedAt));
}
