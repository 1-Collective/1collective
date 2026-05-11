#!/usr/bin/env node
// Apply all SQL migrations in db/migrations/ in order against DATABASE_URL.
// Requires the Supabase project's direct DB connection string.

import { readFileSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import postgres from "postgres";

const __dirname = dirname(fileURLToPath(import.meta.url));
const migrationsDir = resolve(__dirname, "migrations");

const url = process.env.DATABASE_URL;
if (!url) {
  console.error(
    "DATABASE_URL is not set.\n" +
      "Find it in Supabase Dashboard → Project Settings → Database → Connection string\n" +
      "Example: postgresql://postgres:[PASSWORD]@db.xxxx.supabase.co:5432/postgres"
  );
  process.exit(1);
}

const files = readdirSync(migrationsDir)
  .filter((f) => f.endsWith(".sql"))
  .sort();

console.log(`Applying ${files.length} migration(s) from ${migrationsDir}\n`);

const sql = postgres(url, { max: 1, prepare: false });

try {
  for (const file of files) {
    const fullPath = resolve(migrationsDir, file);
    const content = readFileSync(fullPath, "utf8");
    console.log(`→ ${file}`);
    await sql.unsafe(content);
    console.log(`  ✓ applied\n`);
  }
  console.log("All migrations applied successfully.");
} catch (err) {
  console.error("\n✗ Migration failed:", err.message);
  process.exit(1);
} finally {
  await sql.end();
}
