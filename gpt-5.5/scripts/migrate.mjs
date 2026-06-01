import fs from "node:fs/promises";
import path from "node:path";
import postgres from "postgres";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error("DATABASE_URL is required");
}

const sql = postgres(databaseUrl, { max: 1, ssl: process.env.DB_SSL === "false" ? false : "require" });
const migration = await fs.readFile(path.join(process.cwd(), "drizzle", "0000_initial.sql"), "utf8");

try {
  await sql.unsafe(migration);
  console.log("Database migration completed");
} finally {
  await sql.end();
}
