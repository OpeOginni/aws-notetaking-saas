"use client";

import { useCallbackRef } from "@/lib/use-callback-ref";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface AttachmentDTO {
  id: string;
  fileName: string;
  contentType: string;
  size: number;
}

interface NoteDTO {
  id: string;
  title: string;
  content: string;
}

function isImage(contentType: string) {
  return contentType.startsWith("image/");
}

function formatSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default function NoteEditor({
  note,
  initialAttachments,
}: {
  note: NoteDTO;
  initialAttachments: AttachmentDTO[];
}) {
  const router = useRouter();
  const [title, setTitle] = useState(note.title);
  const [content, setContent] = useState(note.content);
  const [attachments, setAttachments] =
    useState<AttachmentDTO[]>(initialAttachments);
  const [status, setStatus] = useState<"idle" | "saving" | "saved">("idle");
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Debounced autosave.
  const save = useCallbackRef(async () => {
    setStatus("saving");
    try {
      const res = await fetch(`/api/notes/${note.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, content }),
      });
      if (res.ok) {
        setStatus("saved");
      } else {
        setStatus("idle");
      }
    } catch {
      setStatus("idle");
    }
  });

  const dirtyRef = useRef(false);
  useEffect(() => {
    if (!dirtyRef.current) {
      dirtyRef.current = true;
      return;
    }
    const t = setTimeout(() => {
      save();
    }, 800);
    return () => clearTimeout(t);
  }, [title, content, save]);

  async function onUpload(files: FileList | null) {
    if (!files || files.length === 0) return;
    setError("");
    setUploading(true);
    try {
      for (const file of Array.from(files)) {
        const fd = new FormData();
        fd.append("file", file);
        const res = await fetch(`/api/notes/${note.id}/attachments`, {
          method: "POST",
          body: fd,
        });
        const data = await res.json();
        if (!res.ok) {
          setError(data.error ?? "Upload failed");
          continue;
        }
        setAttachments((prev) => [
          ...prev,
          {
            id: data.attachment.id,
            fileName: data.attachment.fileName,
            contentType: data.attachment.contentType,
            size: data.attachment.size,
          },
        ]);
      }
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function removeAttachment(attachmentId: string) {
    const res = await fetch(`/api/attachments/${attachmentId}`, {
      method: "DELETE",
    });
    if (res.ok) {
      setAttachments((prev) => prev.filter((a) => a.id !== attachmentId));
    }
  }

  async function deleteNote() {
    if (!confirm("Delete this note and all its attachments?")) return;
    const res = await fetch(`/api/notes/${note.id}`, { method: "DELETE" });
    if (res.ok) {
      router.push("/dashboard");
      router.refresh();
    }
  }

  return (
    <div className="editor">
      <div className="toolbar">
        <Link className="btn secondary sm" href="/dashboard">
          ← Back
        </Link>
        <div className="spacer" />
        {status === "saving" && (
          <span className="saved-hint" style={{ color: "var(--text-dim)" }}>
            Saving…
          </span>
        )}
        {status === "saved" && <span className="saved-hint">✓ Saved</span>}
        <button className="btn danger sm" onClick={deleteNote}>
          Delete
        </button>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="field">
        <input
          className="input"
          style={{ fontSize: 22, fontWeight: 700 }}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Note title"
        />
      </div>

      <div className="field">
        <textarea
          className="textarea"
          value={content}
          onChange={(e) => setContent(e.target.value)}
          placeholder="Start writing…"
        />
      </div>

      <div className="attachments">
        <h3>Attachments</h3>

        <div
          className="uploader"
          onClick={() => fileInputRef.current?.click()}
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            onUpload(e.dataTransfer.files);
          }}
        >
          {uploading
            ? "Uploading…"
            : "Click to upload or drag & drop images and files (max 10 MB)"}
        </div>
        <input
          ref={fileInputRef}
          type="file"
          multiple
          style={{ display: "none" }}
          onChange={(e) => onUpload(e.target.files)}
        />

        {attachments.length > 0 && (
          <div className="attach-grid">
            {attachments.map((a) => (
              <div key={a.id} className="attach-item">
                <button
                  className="remove"
                  onClick={() => removeAttachment(a.id)}
                  title="Remove"
                >
                  ✕
                </button>
                <a
                  href={`/api/attachments/${a.id}/file`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {isImage(a.contentType) ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={`/api/attachments/${a.id}/file`} alt={a.fileName} />
                  ) : (
                    <div className="file-icon">📄</div>
                  )}
                </a>
                <div className="info">
                  {a.fileName}
                  <br />
                  {formatSize(a.size)}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
