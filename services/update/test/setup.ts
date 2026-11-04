import { env } from 'cloudflare:workers';
import { applyD1Migrations } from 'cloudflare:test';
import { beforeAll } from 'vitest';
import type { D1Migration } from '@cloudflare/vitest-plugin';
declare global {
  namespace Cloudflare { interface Env { TEST_MIGRATIONS: D1Migration[] } }
}
beforeAll(async () => { await applyD1Migrations(env.DB, env.TEST_MIGRATIONS); });
