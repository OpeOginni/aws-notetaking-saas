/**
 * Standalone migration runner. Executed at container startup (and locally via
 * `npm run db:migrate`) to apply all SQL migrations in ./drizzle.
 */
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

async function main() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("DATABASE_URL environment variable is not set");
  }

  const useSsl = process.env.DATABASE_SSL !== "false";
  const migrationClient = postgres(connectionString, {
    max: 1,
    ssl: useSsl ? { rejectUnauthorized: false } : false,
  });

  const dbInstance = drizzle(migrationClient);

  console.log("[migrate] applying migrations...");
  await migrate(dbInstance, { migrationsFolder: "./drizzle" });
  console.log("[migrate] migrations applied successfully");

  await migrationClient.end();
  process.exit(0);
}

main().catch((err) => {
  console.error("[migrate] migration failed:", err);
  process.exit(1);
});
