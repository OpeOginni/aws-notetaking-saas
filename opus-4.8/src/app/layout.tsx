import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "NoteSaaS — Your notes, anywhere",
  description: "A simple SaaS notes app with file uploads, built on AWS.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
