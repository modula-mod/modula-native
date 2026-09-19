// N3D Profile fixture. Seeds isolated N1 with own + public profiles, posts, links, follow edge.
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
const apiURL = process.env.MODULA_PROFILE_FIXTURE_URL ?? config.apiURL;
const usesLocalTLS = /localhost|127\.0\.0\.1/.test(apiURL);
const caPath = 'certs/n1-tls/ca.pem';
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

async function ensureAccount(label, {longBio = false} = {}) {
  const suffix = randomBytes(4).toString('hex');
  const email = `native-n1-profile-${label}-${suffix}@example.invalid`;
  const password = `Prof!${randomBytes(24).toString('base64url')}9a`;
  const handle = `n1p${label}${suffix}`.replace(/[^a-z0-9]/gi, '').slice(0, 24);
  const displayName = `${label[0].toUpperCase()}${label.slice(1)} Profile`;
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
  const bio = longBio
    ? 'Building Modula — a modular Social Operating System where your profile becomes your platform. '.repeat(4).trim()
    : `${displayName} fixture bio for N3D Profile acceptance.`;
  try {
    const me = await request('GET', `/v1/profiles/${handle}`, null, session.accessToken);
    await request('PATCH', '/v1/profiles/me', {
      displayName,
      bio,
      expectedVersion: me.version ?? 1,
    }, session.accessToken);
  } catch (error) {
    // Best-effort — write may be limited on some environments.
  }
  return {email, password, handle, accessToken: session.accessToken, accountId: session.accountId};
}

const report = [];

const login = await request('POST', '/v1/sessions', {email: config.email, password: config.password}, null);
token = login.accessToken;
report.push('signed in as N1 fixture account');

let me;
try {
  me = await request('GET', '/v1/accounts/me', null, token);
  const profile = await request('GET', `/v1/profiles/${me.primaryHandle}`, null, token);
  report.push(`current profile @${profile.handle} posts=${profile.postCount} followers=${profile.followerCount}`);
  await request('PATCH', '/v1/profiles/me', {
    displayName: profile.displayName,
    bio: (profile.bio && profile.bio.length > 40)
      ? profile.bio
      : 'N3D fixture bio — Profile is the identity surface. Cover and avatar may be absent until media upload ships.',
    expectedVersion: profile.version ?? 1,
  }, token);
  report.push('updated own bio via PATCH /v1/profiles/me');
} catch (error) {
  report.push(`own profile: ${error.message}`);
}

const publicUser = await ensureAccount('sophia', {longBio: true});
report.push(`created public user @${publicUser.handle}`);

const emptyUser = await ensureAccount('quiet');
report.push(`created empty-posts user @${emptyUser.handle}`);

try {
  const sophia = await request('GET', `/v1/profiles/${publicUser.handle}`, null, token);
  await request('POST', `/v1/profiles/${sophia.id}/follow`, {}, token);
  report.push(`followed @${publicUser.handle}`);
} catch (error) {
  report.push(`follow: ${error.message}`);
}

for (const text of [
  'First Profile fixture post — Overview preview.',
  'Second post with enough text to exercise the Posts rail.',
  'Third post confirming cursor pagination candidates.',
]) {
  try {
    await request('POST', '/v1/posts', {text, feed: 'following', audience: 'public'}, publicUser.accessToken);
    report.push(`post as @${publicUser.handle}`);
  } catch (error) {
    report.push(`post: ${error.message}`);
  }
}

try {
  const posts = await request('GET', `/v1/profiles/${publicUser.handle}/posts?limit=5`, null, token);
  report.push(`sophia posts=${posts.items?.length ?? 0} hasMore=${Boolean(posts.hasMore)}`);
  const followers = await request('GET', `/v1/profiles/${publicUser.handle}/followers?limit=5`, null, token);
  report.push(`sophia followers=${followers.items?.length ?? 0}`);
  const following = await request('GET', `/v1/profiles/${me?.primaryHandle ?? config.handle}/following?limit=5`, null, token);
  report.push(`me following=${following.items?.length ?? 0}`);
} catch (error) {
  report.push(`lists: ${error.message}`);
}

try {
  const modules = await request('GET', `/v1/profiles/${publicUser.handle}/modules`, null, token).catch(err => {
    throw err;
  });
  report.push(`modules endpoint unexpected success items=${modules.items?.length ?? 0}`);
} catch (error) {
  report.push(`modules endpoint absent/unavailable (expected): ${error.message}`);
}

await request('DELETE', '/v1/sessions/current', null, token).catch(() => {});
await request('DELETE', '/v1/sessions/current', null, publicUser.accessToken).catch(() => {});
await request('DELETE', '/v1/sessions/current', null, emptyUser.accessToken).catch(() => {});
token = undefined;

console.log('N3D profile fixture (no secrets):');
for (const line of report) console.log('-', line);
