// N3C Home fixture. Seeds isolated N1 DB with follows + posts via public Greenfield contracts.
// Never targets production. Does not print passwords or tokens.
import https from 'node:https';
import {readFileSync, existsSync} from 'node:fs';
import {randomBytes} from 'node:crypto';

const file = '.env.n1.local';
if (!existsSync(file)) {
  console.error('Missing .env.n1.local — run scripts/n1/fixture.mjs first.');
  process.exit(1);
}
const config = JSON.parse(readFileSync(file, 'utf8'));
const apiURL = process.env.MODULA_HOME_FIXTURE_URL ?? config.apiURL;
const usesLocalTLS = /localhost|127\.0\.0\.1/.test(apiURL);
const caPath = 'artifacts/n1-tls/ca.pem';
const ca = usesLocalTLS && existsSync(caPath) ? readFileSync(caPath) : undefined;

let token;

async function request(method, path, body, authToken = token) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, apiURL);
    const payload = body ? JSON.stringify(body) : undefined;
    const req = https.request(url, {
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
          if (!result.ok) reject(new Error(`${method} ${path}: ${result.error?.code ?? res.statusCode}${result.error?.message ? ` (${result.error.message})` : ''}`));
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

async function ensureAccount(label) {
  const suffix = randomBytes(4).toString('hex');
  const email = `native-n1-home-${label}-${suffix}@example.invalid`;
  const password = `Home!${randomBytes(24).toString('base64url')}9a`;
  const handle = `n1${label}${suffix}`.replace(/[^a-z0-9]/gi, '').slice(0, 24);
  const displayName = `${label[0].toUpperCase()}${label.slice(1)} Home`;
  let registered;
  try {
    registered = await request('POST', '/v1/accounts/register', {
      email,
      password,
      handle,
      displayName,
      acceptedTerms: true,
    }, null);
  } catch (error) {
    if (!String(error.message).includes('CONFLICT')) throw error;
  }
  if (registered?.verificationToken) {
    await request('POST', '/v1/accounts/verify-email', {
      token: registered.verificationToken,
    }, null);
  }
  const session = await request('POST', '/v1/sessions', {email, password}, null);
  return {email, password, handle, accessToken: session.accessToken, accountId: session.accountId, actorId: session.actorId};
}

const report = [];

const login = await request('POST', '/v1/sessions', {email: config.email, password: config.password}, null);
token = login.accessToken;
report.push('signed in as N1 fixture account');

const companions = [];
for (const label of ['sophia', 'marcus', 'alex']) {
  try {
    const account = await ensureAccount(label);
    companions.push(account);
    report.push(`created companion ${label} → @${account.handle}`);
  } catch (error) {
    report.push(`companion ${label}: ${error.message}`);
  }
}

for (const companion of companions) {
  try {
    const profile = await request('GET', `/v1/profiles/${companion.handle}`, null, token);
    await request('POST', `/v1/profiles/${profile.id}/follow`, {}, token);
    report.push(`followed @${companion.handle}`);
  } catch (error) {
    report.push(`follow @${companion.handle}: ${error.message}`);
  }
}

const seedPosts = [
  {who: 0, text: 'Morning light on the river — keeping the Following feed honest.', feed: 'following'},
  {who: 1, text: 'Shipping notes: denser rails, quieter chrome.', feed: 'following'},
  {who: 2, text: 'If your Home is quiet, Discover is where people appear.', feed: 'following'},
  {who: 0, text: 'For You ranking-v1 should surface engaged public posts without pretending to be AI.', feed: 'forYou'},
  {who: 1, text: 'Module updates belong in Modules — Vault Notes 1.7 is live on the fixture.', feed: 'modules', module: true},
];

for (const seed of seedPosts) {
  const author = companions[seed.who];
  if (!author) continue;
  try {
    const body = {
      text: seed.text,
      feed: seed.feed,
      audience: 'public',
    };
    await request('POST', '/v1/posts', body, author.accessToken);
    report.push(`post as @${author.handle} (${seed.feed})`);
  } catch (error) {
    report.push(`post as @${author.handle}: ${error.message}`);
  }
}

try {
  const following = await request('GET', '/v1/feed/home?mode=following&limit=10', null, token);
  report.push(`following items=${following.items?.length ?? 0} ranking=${following.rankingVersion ?? 'n/a'}`);
  const forYou = await request('GET', '/v1/feed/home?mode=forYou&limit=10', null, token);
  report.push(`forYou items=${forYou.items?.length ?? 0} ranking=${forYou.rankingVersion ?? 'n/a'}`);
  const modules = await request('GET', '/v1/feed/home?mode=modules&limit=10', null, token);
  report.push(`modules items=${modules.items?.length ?? 0} ranking=${modules.rankingVersion ?? 'n/a'}`);
} catch (error) {
  report.push(`feed probe: ${error.message}`);
}

await request('DELETE', '/v1/sessions/current', null, token).catch(() => {});
token = undefined;

console.log('N3C home fixture (no secrets):');
for (const line of report) console.log('-', line);
