import { defineConfig } from 'vitest/config';

// Integration suites apply `db/schema.sql` to the same isolated PostgreSQL database.
// Concurrent `create ... if not exists` DDL from several workers can race
// (duplicate pg_class entries), so serialize test files whenever a database is
// configured. Without a database the DB suites skip and files stay parallel.
const databaseConfigured = Boolean(process.env.AUTH_TEST_DATABASE_URL);

export default defineConfig({
  test: {
    include: ['packages/**/*.test.ts', 'apps/api/src/**/*.test.ts'],
    environment: 'node',
    fileParallelism: !databaseConfigured,
  },
});
