import { exportJWK, generateKeyPair, SignJWT, type JWTPayload } from 'jose';

/**
 * A stand-in Cloudflare Access team for tests: a real RS256 key pair, its public half
 * served at the team's certificate URL, and tokens signed the way Access signs them.
 * The team domain and audience match the bindings in vitest.config.ts.
 */
export const TEAM_DOMAIN = 'https://fanbar-test.cloudflareaccess.com';
export const AUDIENCE = 'fanbar-test-audience';
const KEY_ID = 'fanbar-test-key';

const signing = await generateKeyPair('RS256', { extractable: true });
const certificates = { keys: [{ ...(await exportJWK(signing.publicKey)), kid: KEY_ID, alg: 'RS256', use: 'sig' }] };

/** Serves the test team's certificates; every other request goes to the real fetch. */
export function serveAccessCertificates() {
  const original = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url === `${TEAM_DOMAIN}/cdn-cgi/access/certs`) return Promise.resolve(Response.json(certificates));
    return original(input, init);
  }) as typeof fetch;
}

export async function accessToken(claims: JWTPayload = {}, options: {
  key?: CryptoKey; issuer?: string; audience?: string; expiresIn?: string | number;
} = {}) {
  return new SignJWT({ email: 'maintainer@example.com', ...claims })
    .setProtectedHeader({ alg: 'RS256', kid: KEY_ID })
    .setSubject('7f1c2b54-0000-4000-8000-000000000001')
    .setIssuer(options.issuer ?? TEAM_DOMAIN)
    .setAudience(options.audience ?? AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(options.expiresIn ?? '1h')
    .sign(options.key ?? signing.privateKey);
}

/** Header a request carries after passing Cloudflare Access. */
export const adminHeaders = async (extra: Record<string, string> = {}) => ({
  'Cf-Access-Jwt-Assertion': await accessToken(), ...extra,
});
