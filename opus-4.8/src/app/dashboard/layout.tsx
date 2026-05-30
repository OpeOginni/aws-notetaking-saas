import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import LogoutButton from "./logout-button";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getSession();
  if (!session) redirect("/login");

  return (
    <div>
      <nav className="nav">
        <Link className="brand" href="/dashboard">
          📝 NoteSaaS
        </Link>
        <div className="spacer" />
        <span className="user">{session.email}</span>
        <LogoutButton />
      </nav>
      <div className="container">{children}</div>
    </div>
  );
}
