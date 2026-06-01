// Plain-ESM migration runner used at container startup. Depends only on
// `drizzle-orm` and `postgres`, both of which are copied into the runtime image.
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error("[migrate] DATABASE_URL is not set");
  process.exit(1);
}

const useSsl = process.env.DATABASE_SSL !== "false";
const client = postgres(connectionString, {
  max: 1,
  ssl: useSsl ? { rejectUnauthorized: false } : false,
});

const db = drizzle(client);

try {
  console.log("[migrate] applying migrations...");
  await migrate(db, { migrationsFolder: "./drizzle" });
  console.log("[migrate] migrations applied successfully");
  await client.end();
  process.exit(0);
} catch (err) {
  console.error("[migrate] migration failed:", err);
  await client.end().catch(() => {});
  process.exit(1);
}
