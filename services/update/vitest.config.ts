import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-plugin';
import { defineConfig } from 'vitest/config';
export default defineConfig({
  plugins: [cloudflareTest(async () => ({
    wrangler: { configPath: './wrangler.jsonc' },
    miniflare: { bindings: {
      TEST_MIGRATIONS: await readD1Migrations('./migrations'),
      LIMIT_SALT: 'test-only-not-a-production-secret',
    } },
  }))],
  test: { include: ['test/**/*.test.ts'], setupFiles: ['./test/setup.ts'] },
});
