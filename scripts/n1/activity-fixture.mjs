// N3A Activity fixture extension. Run on a Mac with the N1 TLS tunnel / VPS fixture live.
// Does not print passwords or tokens. Extends the N1 account with social activity via public contracts
// when those endpoints accept the fixture session.
import https from 'node:https';
import {readFileSync, existsSync} from 'node:fs';

const file = '.env.n1.local';
if (!existsSync(file)) {
  console.error('Missing .env.n1.local — run scripts/n1/fixture.mjs first.');
  process.exit(1);
}
const config = JSON.parse(readFileSync(file, 'utf8'));
const caPath = 'artifacts/n1-tls/ca.pem';
const ca = existsSync(caPath) ? readFileSync(caPath) : undefined;
let token;

async function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, config.apiURL);
    const req = https.request(url, {
      method,
      ca,
      rejectUnauthorized: Boolean(ca),
      headers: {
        ...(body ? {'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(JSON.stringify(body))} : {}),
        ...(token ? {Authorization: `Bearer ${token}`} : {}),
        Accept: 'application/json',
      },
    }, res => {
      let wire = '';
      res.on('data', d => wire += d);
      res.on('end', () => {
        try {
          const result = JSON.parse(wire);
          if (!result.ok) reject(new Error(`${method} ${path}: ${result.error?.code ?? res.statusCode}`));
          else resolve(result.data);
        } catch {
          reject(new Error(`Invalid envelope ${method} ${path} HTTP ${res.statusCode}`));
        }
      });
    });
    req.on('error', err => reject(err));
    req.end(body ? JSON.stringify(body) : undefined);
  });
}

const login = await request('POST', '/v1/sessions', {email: config.email, password: config.password});
token = login.accessToken;

const probes = [
  ['GET', '/v1/notifications?limit=5'],
  ['GET', '/v1/connections/requests?limit=5'],
  ['GET', '/v1/activity'],
];

const report = [];
for (const [method, path] of probes) {
  try {
    const data = await request(method, path);
    const count = Array.isArray(data) ? data.length : (data?.items?.length ?? data?.notifications?.length ?? Object.keys(data ?? {}).length);
    report.push(`${method} ${path}: OK keys/count=${count}`);
  } catch (error) {
    report.push(`${method} ${path}: ${error.message}`);
  }
}

console.log('N3A activity fixture probe (no secrets):');
for (const line of report) console.log('-', line);
console.log('Seed social events through normal Greenfield flows once VPS source confirms create APIs.');
console.log('Do not insert malformed rows. Re-run after provisioning companion accounts for follows/mentions.');

await request('DELETE', '/v1/sessions/current').catch(() => {});
token = undefined;
