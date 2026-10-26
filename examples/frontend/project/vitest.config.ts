// Follows rules/frontend/testing.md: Vitest, tests beside their source; @/ resolves from tsconfig.json's paths.
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: { include: ['src/**/*.test.{ts,tsx}'] },
});
