// N3C visibility probe against isolated N1. Never targets production.
// Uses the existing fixture account only (no new registrations) to avoid rate limits.
import https from 'node:https';
import http from 'node:http';
import {readFileSync, existsSync} from 'node:fs';
import {randomBytes} from 'node:crypto';

const file = process.env.MODULA_N1_ENV_FILE ?? '.env.n1.local';
if (!existsSync(file)) {
  console.error(`Missing ${file}`);
  process.exit(1);
}
const config = JSON.parse(readFileSync(file, 'utf8'));
const apiURL = process.env.MODULA_HOME_FIXTURE_URL ?? config.apiURL;
const usesLocalTLS = /^https:\/\/(localhost|127\.0\.0\.1)/.test(apiURL);
const caPath = 'artifacts/n1-tls/ca.pem';
const ca = usesLocalTLS && existsSync(caPath) ? readFileSync(caPath) : undefined;
const transport = apiURL.startsWith('http:') ? http : https;

let token;

async function request(method, path, body, authToken = token) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, apiURL);
    const payload = body ? JSON.stringify(body) : undefined;
    const req = transport.request(url, {
      method,
      ...(ca ? {ca, rejectUnauthorized: true} : {}),
      headers: {
        Accept: 'application/json',
        ...(payload ? {'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload)} : {}),
        ...(authToken ? {Authorization: `Bearer ${authToken}`} : {}),
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
    req.on('error', reject);
    req.end(payload);
  });
}

const report = [];
const login = await request('POST', '/v1/sessions', {email: config.email, password: config.password}, null);
token = login.accessToken;
report.push('signed in as N1 fixture account');

const marker = randomBytes(4).toString('hex');
const owned = await request('POST', '/v1/posts', {
  text: `visibility-owned-${marker}`,
  feed: 'forYou',
  audience: 'public',
}, token);
report.push(`created owned post ${owned.id}`);

const forYou = await request('GET', '/v1/feed/home?mode=forYou&limit=40', null, token);
const foreign = (forYou.items ?? []).find(p => p.id !== owned.id && p.author?.id && p.author.id !== login.actorId);
if (!foreign) {
  console.error('No foreign forYou post available for block/mute probe');
  process.exit(1);
}
const targetProfileId = foreign.author.id;
const targetPostId = foreign.id;
report.push(`target post ${targetPostId} author ${foreign.author.handle ?? targetProfileId}`);

const before = await request('GET', '/v1/feed/home?mode=forYou&limit=50', null, token);
const beforeIds = new Set((before.items ?? []).map(p => p.id));
report.push(`before contains target=${beforeIds.has(targetPostId)} owned=${beforeIds.has(owned.id)}`);

await request('POST', `/v1/profiles/${targetProfileId}/block`, {}, token);
report.push('blocked target author');
const afterBlock = await request('GET', '/v1/feed/home?mode=forYou&limit=50', null, token);
const afterBlockIds = new Set((afterBlock.items ?? []).map(p => p.id));

await request('DELETE', `/v1/profiles/${targetProfileId}/block`, {}, token);
await request('POST', `/v1/profiles/${targetProfileId}/mute`, {}, token);
report.push('unmuted block; muted target author');
const afterMute = await request('GET', '/v1/feed/home?mode=forYou&limit=50', null, token);
const afterMuteIds = new Set((afterMute.items ?? []).map(p => p.id));

await request('DELETE', `/v1/posts/${owned.id}`, null, token);
report.push('deleted owned post');
const afterDelete = await request('GET', '/v1/feed/home?mode=forYou&limit=50', null, token);
const afterDeleteIds = new Set((afterDelete.items ?? []).map(p => p.id));

// cleanup mute
await request('DELETE', `/v1/profiles/${targetProfileId}/mute`, {}, token).catch(() => {});

const checks = [
  ['forYou had target before moderation', beforeIds.has(targetPostId)],
  ['block excludes target from forYou', !afterBlockIds.has(targetPostId)],
  ['mute excludes target from forYou', !afterMuteIds.has(targetPostId)],
  ['deleted owned post excluded', !afterDeleteIds.has(owned.id)],
  ['rankingVersion forYou', afterBlock.rankingVersion === 'ranking-v1'],
];

let failed = 0;
for (const [label, ok] of checks) {
  report.push(`${ok ? 'PASS' : 'FAIL'} ${label}`);
  if (!ok) failed += 1;
}

await request('DELETE', '/v1/sessions/current', null, token).catch(() => {});
console.log('N3C visibility probe (no secrets):');
for (const line of report) console.log('-', line);
process.exit(failed ? 1 : 0);
