// Existing Greenfield API, isolated environment. Invoked by a dedicated systemd service.
import {readFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
const env = JSON.parse(readFileSync('/root/modula-native-n1/environment.json','utf8'));
const worker=process.argv.includes('--worker');
if(worker){
 env.MODULA_DATABASE_URL=env.N1_WORKER_DATABASE_URL;
 env.MODULA_MAIL_TRANSPORT='disabled';env.MODULA_MAIL_PROVISIONER_MODE='disabled';
 env.MODULA_WORKER_EMPTY_POLL_BACKOFF_MS='1000';
}
const child = spawn('pnpm', ['exec','tsx','src/main.ts'], {
  cwd:`/root/modula-latest/services/greenfield-${worker?'worker':'api'}`, env:{...process.env,...env}, stdio:'inherit',
});
for (const signal of ['SIGTERM','SIGINT']) process.on(signal, () => child.kill(signal));
child.on('exit', code => process.exit(code ?? 1));
