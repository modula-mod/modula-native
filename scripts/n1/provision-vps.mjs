// Run on modula-vps. Uses the existing Greenfield fixture and release tooling.
// No account or product record is inserted directly into SQL.
import {mkdirSync, existsSync, writeFileSync, readFileSync, copyFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
const root = '/root/modula-latest';
const state = '/root/modula-native-n1';
const api = `${root}/services/greenfield-api`;
mkdirSync(state, {recursive: true, mode: 0o700});
function save(name, value) {writeFileSync(`${state}/${name}`, JSON.stringify(value, null, 2), {mode: 0o600});}
let fixture;
if (existsSync(`${state}/database.json`)) fixture = JSON.parse(readFileSync(`${state}/database.json`, 'utf8'));
else {
  const {createGreenfieldVerifierDatabaseFixture} = await import(`${root}/scripts/greenfield-backend-v1-database-fixture.mjs`);
  fixture = createGreenfieldVerifierDatabaseFixture('native_n1');
  if (!fixture) throw new Error('Existing preview database fixture unavailable');
  save('database.json', fixture);
}
const lines = execFileSync('docker', ['inspect', 'modula-preview-greenfield-postgres-1', '--format', '{{range .Config.Env}}{{println .}}{{end}}'], {encoding: 'utf8'});
const values = Object.fromEntries(lines.trim().split('\n').map(line => [line.slice(0,line.indexOf('=')), line.slice(line.indexOf('=')+1)]));
const db = new URL(fixture.migratorUrl);
db.username = 'modula_api'; db.password = values.MODULA_API_PASSWORD;
const envFile = `${state}/environment.json`;
const env = existsSync(envFile) ? JSON.parse(readFileSync(envFile, 'utf8')) : {
  NODE_ENV: 'development', MODULA_ENVIRONMENT: 'development', MODULA_API_PORT: '4021', MODULA_API_HOST: '127.0.0.1',
  MODULA_PUBLIC_API_URL: 'https://localhost:44021', MODULA_ALLOWED_ORIGINS: 'https://localhost:44021',
  MODULA_DATABASE_URL: db.toString(), MODULA_DATABASE_MIGRATOR_URL: fixture.migratorUrl,
  MODULA_LOG_LEVEL: 'warn', MODULA_SESSION_PEPPER: randomBytes(32).toString('hex'),
  MODULA_CONNECTOR_CREDENTIAL_ENCRYPTION_KEY: randomBytes(32).toString('base64'),
  MODULA_AI_PROVIDER_CREDENTIAL_ENCRYPTION_KEY: randomBytes(32).toString('base64'),
  MODULA_ATPROTO_OAUTH_ENCRYPTION_KEY: randomBytes(32).toString('base64'),
  MODULA_MEDIA_ROOT: `${state}/media`, MODULA_REGISTRATION_MODE: 'open',
  GREENFIELD_MODULE_REGISTRY_ENABLED: 'true', GREENFIELD_MODULE_INSTALLATION_ENABLED: 'true',
  GREENFIELD_MODULE_DECLARATIVE_CONTRIBUTIONS_ENABLED: 'true', GREENFIELD_MODULE_FIRST_PARTY_EXECUTION_ENABLED: 'true',
};
if (!env.N1_WORKER_DATABASE_URL) {
  const password = randomBytes(32).toString('hex');
  const role = 'modula_native_n1_worker';
  execFileSync('docker', ['exec','-i','modula-preview-greenfield-postgres-1','psql','-U','modula_admin','-d','modula','-v','ON_ERROR_STOP=1'], {
    input:`CREATE ROLE ${role} LOGIN NOSUPERUSER NOBYPASSRLS IN ROLE modula_worker PASSWORD '${password}';`, stdio:['pipe','pipe','pipe'],
  });
  const worker = new URL(db);worker.username=role;worker.password=password;
  env.N1_WORKER_DATABASE_URL=worker.toString();
}
save('environment.json', env);
// Backend executes with normal modula_api privileges; fixture helper's test superuser is never the API role.
const childEnv = {...process.env, ...env};
execFileSync('pnpm', ['exec','tsx','scripts/db-migrate.ts'], {cwd: api, env: childEnv, stdio: 'pipe'});
const product = `${state}/vault-notes-1.7.0`;
if (!existsSync(product)) execFileSync('git',['clone','--local','--branch','vault-notes-v1.7.0','/root/modula-mod/modula-vault-notes',product],{stdio:'pipe'});
// Published artifacts are ignored release outputs, verified against the immutable tag by the CLI.
mkdirSync(`${product}/release`, {recursive:true});
for (const file of ['vault-notes-v1.7.0.provenance.json','modula-vault-notes-1.7.0.tgz']) copyFileSync(`/root/modula-mod/modula-vault-notes/release/${file}`, `${product}/release/${file}`);
execFileSync('pnpm', ['exec','tsx','scripts/publish-mps-products.ts','--apply','--product-root',product], {cwd: api, env: childEnv, stdio: 'pipe'});
console.log('N1 isolated database migrated; canonical Vault 1.7.0 published through existing release CLI.');
