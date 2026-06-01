import Link from "next/link";
import { loginAction } from "@/app/actions";

export default function Login({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  return <LoginPage searchParams={searchParams} />;
}

async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return (
    <main className="auth-shell">
      <form className="auth-card" action={loginAction}>
        <p className="eyebrow">Welcome back</p>
        <h1>Log in</h1>
        {params.error && <p className="error">{params.error}</p>}
        <label>Email<input name="email" type="email" required autoComplete="email" /></label>
        <label>Password<input name="password" type="password" required autoComplete="current-password" /></label>
        <button className="button primary full" type="submit">Open dashboard</button>
        <p className="muted">No account? <Link href="/signup">Create one</Link></p>
      </form>
    </main>
  );
}
