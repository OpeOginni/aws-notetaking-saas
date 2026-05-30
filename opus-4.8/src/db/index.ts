import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error("DATABASE_URL environment variable is not set");
}

// SSL handling:
//   - Local dev (DATABASE_SSL=false): no TLS.
//   - Production (RDS): TLS enabled. We do not bundle the RDS CA bundle, so we
//     enable TLS but skip strict chain verification via rejectUnauthorized:false.
//     Connections still travel inside the private VPC subnets.
const useSsl = process.env.DATABASE_SSL !== "false";
const client = postgres(connectionString, {
  max: 10,
  ssl: useSsl ? { rejectUnauthorized: false } : false,
});

export const db = drizzle(client, { schema });
export { schema };
