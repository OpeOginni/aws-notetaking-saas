import type { Metadata } from "next";
import Link from "next/link";
import { getCurrentUser } from "@/lib/auth";
import { logoutAction } from "./actions";
import "./styles.css";

export const metadata: Metadata = {
  title: "Fieldnotes Cloud",
  description: "A secure SaaS notes app with image and file uploads."
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const user = await getCurrentUser();

  return (
    <html lang="en">
      <body>
        <header className="topbar">
          <Link href="/" className="brand">Fieldnotes Cloud</Link>
          <nav>
            {user ? (
              <>
                <Link href="/dashboard">Dashboard</Link>
                <form action={logoutAction}>
                  <button className="link-button" type="submit">Log out</button>
                </form>
              </>
            ) : (
              <>
                <Link href="/login">Log in</Link>
                <Link className="nav-cta" href="/signup">Start free</Link>
              </>
            )}
          </nav>
        </header>
        {children}
      </body>
    </html>
  );
}
