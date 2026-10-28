// rules/database/prisma.md
import 'dotenv/config'; // the Prisma 7 CLI does not load .env itself
import { defineConfig, env } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema',
  migrations: { path: 'prisma/migrations' },
  datasource: { url: env('DIRECT_URL') }, // the CLI migrates; without a pooler, DATABASE_URL
});
