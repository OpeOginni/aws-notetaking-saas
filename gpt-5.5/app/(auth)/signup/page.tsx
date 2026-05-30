import Link from "next/link";
import { signUpAction } from "@/app/actions";

export default function Signup({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  return <SignupPage searchParams={searchParams} />;
}

async function SignupPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return (
    <main className="auth-shell">
      <form className="auth-card" action={signUpAction}>
        <p className="eyebrow">Start organized</p>
        <h1>Create account</h1>
        {params.error && <p className="error">{params.error}</p>}
        <label>Name<input name="name" required autoComplete="name" /></label>
        <label>Email<input name="email" type="email" required autoComplete="email" /></label>
        <label>Password<input name="password" type="password" minLength={8} required autoComplete="new-password" /></label>
        <button className="button primary full" type="submit">Create workspace</button>
        <p className="muted">Already registered? <Link href="/login">Log in</Link></p>
      </form>
    </main>
  );
}
