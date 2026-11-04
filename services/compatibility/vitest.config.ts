import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-plugin';
import { defineConfig } from 'vitest/config';
export default defineConfig({
  plugins: [cloudflareTest(async () => ({
    wrangler: { configPath: './wrangler.jsonc' },
    miniflare: { bindings: {
      TEST_MIGRATIONS: await readD1Migrations('./migrations'),
      LIMIT_SALT: 'test-only-not-a-production-secret',
      ACCESS_TEAM_DOMAIN: 'https://fanbar-test.cloudflareaccess.com',
      ACCESS_AUD: 'fanbar-test-audience',
    },
    // Stands in for the update service so the UPDATE_SERVICE binding resolves; tests that
    // exercise update statistics pass their own UPDATE_SERVICE in env.
    workers: [{
      name: 'fanbar-update-local',
      modules: true,
      compatibilityDate: '2026-10-13',
      script: `import { WorkerEntrypoint } from 'cloudflare:workers';
        export class UpdateAdmin extends WorkerEntrypoint { async stats(range) { return { range, stub: true }; } }
        export default { fetch() { return new Response(null, { status: 404 }); } };`,
    }] },
  }))],
  test: { include: ['test/**/*.test.ts'], setupFiles: ['./test/setup.ts'] },
});
