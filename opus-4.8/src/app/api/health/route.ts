import { NextResponse } from "next/server";

// Lightweight liveness probe for the ALB target group health check.
export async function GET() {
  return NextResponse.json({ status: "ok", time: new Date().toISOString() });
}
