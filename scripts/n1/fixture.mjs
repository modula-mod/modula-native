// Mac harness. Password and verification/session tokens never reach stdout.
import https from 'node:https';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {randomBytes,randomUUID} from 'node:crypto';
const file='.env.n1.local';
const config=existsSync(file)?JSON.parse(readFileSync(file,'utf8')):{
  apiURL:'https://localhost:44021',email:'native-n1-integration@example.invalid',
  password:randomBytes(32).toString('base64url'),handle:'native-n1-integration',
};
// .gitignore covers .env.* before this is ever written.
writeFileSync(file,JSON.stringify(config,null,2),{mode:0o600});
const ca=readFileSync('artifacts/n1-tls/ca.pem');
let token;
async function request(method,path,body) {
  return new Promise((resolve,reject)=>{
    const req=https.request(new URL(path,config.apiURL),{method,ca,headers:{...(body?{'Content-Type':'application/json','Content-Length':Buffer.byteLength(JSON.stringify(body))}:{}),...(token?{Authorization:`Bearer ${token}`}:{})}},res=>{
      let wire='';res.on('data',data=>wire+=data);res.on('end',()=>{
        try {const result=JSON.parse(wire);if(!result.ok) reject(new Error(`${method} ${path}: ${result.error?.code??result.code??res.statusCode}`));else resolve(result.data);}catch{reject(new Error(`Invalid API envelope: ${method} ${path} HTTP ${res.statusCode}, bytes ${wire.length}`));}
      });
    });req.on('error',()=>reject(new Error('N1 API transport unavailable')));req.end(body?JSON.stringify(body):undefined);
  });
}
const modulePath='/v1/modules/digital.modula.vault-notes';
const notesPath=`${modulePath}/records/note`;
if(!config.accountId){
 let registered;
 try { registered=await request('POST','/v1/accounts/register',{email:config.email,password:config.password,handle:config.handle,displayName:'Modula Native Phase N1 Integration',acceptedTerms:true}); } catch(error) { if(!error.message.endsWith('CONFLICT'))throw error; }
 if(registered) {
 const verified=await request('POST','/v1/accounts/verify-email',{token:registered.verificationToken});
 config.accountId=verified.account.accountId;
 writeFileSync(file,JSON.stringify(config,null,2),{mode:0o600});
 }
}
const login=await request('POST','/v1/sessions',{email:config.email,password:config.password});token=login.accessToken;
try {
 const me=await request('GET','/v1/accounts/me');if(me.status!=='active')throw new Error(`Fixture account inactive; keys: ${Object.keys(me).join(',')}`);
 config.accountId=me.accountId;writeFileSync(file,JSON.stringify(config,null,2),{mode:0o600});
 const preview=await request('POST',`${modulePath}/install-preview`,{version:'1.7.0',platform:'ios'});
 if(!preview.compatible)throw new Error(`Vault incompatible: ${JSON.stringify(preview.incompatibilityReasons)}`);
 await request('POST',`${modulePath}/install`,{version:'1.7.0',platform:'ios',approvedPermissions:preview.permissions.map(p=>p.permission),idempotencyKey:'native-n1-vault-install-v1'});
 for(let attempt=0;attempt<30;attempt++){
   const installed=await request('GET','/v1/modules/installed/digital.modula.vault-notes');
   if(installed.status==='enabled')break;
   if(['installed','disabled'].includes(installed.status)) await request('POST',`${modulePath}/enable`,{idempotencyKey:'native-n1-vault-enable-v1'});
   if(attempt===29)throw new Error(`Vault lifecycle did not enable (${installed.status})`);
   await new Promise(resolve=>setTimeout(resolve,1000));
 }
 const list=await request('GET',`${notesPath}?limit=100&recordState=active`);
 console.log('Record list envelope keys:',Object.keys(list).join(','));
 const rows=list.items??list.records??[];
 const transientPrefixes=['N1 RN Bridge UI','NRN Bridge UI','N1 Release Bridge','NativeVaultBridge-','NativeReleaseBridge-','N1 Swift Bridge','N1 API CRUD'];
 for(const row of rows.filter(row=>transientPrefixes.some(prefix=>row.data.title.startsWith(prefix)))){
   await request('DELETE',`${notesPath}/${row.record_id}`,{expectedRevision:row.revision});
 }
 for(let index=1;index<=4;index++){
   const title=`N1 Fixture ${index}`;const text=`Deterministic native integration note ${index}.`;
   const data={title,document:{schemaVersion:'1.0.0',blocks:[{id:'block-1',type:'paragraph',text}]},plainTextProjection:text,tagIds:[],pinned:false,favourite:false,archived:false,dataSchemaVersion:'1.0.0'};
   const existing=rows.find(row=>row.data.title===title);
   if(existing)await request('PATCH',`${notesPath}/${existing.record_id}`,{data,expectedRevision:existing.revision});
   else await request('POST',notesPath,{data});
 }
 const created=await request('POST',notesPath,{data:{title:'N1 API CRUD proof',document:{schemaVersion:'1.0.0',blocks:[{id:'block-1',type:'paragraph',text:'Native CRUD proof'}]},plainTextProjection:'Native CRUD proof',tagIds:[],pinned:false,favourite:false,archived:false,dataSchemaVersion:'1.0.0'}});
 const recordId=created.record_id;
 if(!recordId)throw new Error(`Record response keys: ${Object.keys(created).join(',')}`);
 const loaded=await request('GET',`${notesPath}/${recordId}`);
 const updated=await request('PATCH',`${notesPath}/${recordId}`,{data:{...loaded.data,title:'N1 API CRUD edited'},expectedRevision:loaded.revision});
 const reloaded=await request('GET',`${notesPath}/${recordId}`);
 if(reloaded.data.title!=='N1 API CRUD edited')throw new Error('Edit did not persist');
 await request('DELETE',`${notesPath}/${recordId}`,{expectedRevision:updated.revision});
 const final=await request('GET',`${notesPath}?limit=100&recordState=active`);
 if((final.items??final.records??[]).some(row=>row.record_id===recordId))throw new Error('Deletion did not persist');
 console.log('N1 fixture: verified active account; Vault 1.7.0 enabled; four deterministic notes; API create/read/edit/delete PASS.');
} finally {await request('DELETE','/v1/sessions/current').catch(()=>console.log('Fixture session logout requires inspection'));token=undefined;}
