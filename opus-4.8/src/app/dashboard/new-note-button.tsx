"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function NewNoteButton() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function createNote() {
    setLoading(true);
    const res = await fetch("/api/notes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: "Untitled note", content: "" }),
    });
    if (res.ok) {
      const data = await res.json();
      router.push(`/dashboard/notes/${data.note.id}`);
    } else {
      setLoading(false);
    }
  }

  return (
    <button className="btn" onClick={createNote} disabled={loading}>
      {loading ? "Creating…" : "+ New note"}
    </button>
  );
}
