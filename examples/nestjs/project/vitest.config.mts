// rules/server/nestjs.md: SWC keeps the decorator metadata Nest's constructor injection reads
import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [swc.vite()],
  resolve: { tsconfigPaths: true }, // @/ from tsconfig.json
  test: { include: ['src/**/*.test.ts', 'test/**/*.test.ts'] },
});
