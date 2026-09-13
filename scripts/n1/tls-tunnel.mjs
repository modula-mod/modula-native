// Local TLS terminator for the authenticated SSH tunnel to the isolated VPS API.
// Trust its development CA only in the acceptance simulator; no trust bypass in the app.
import https from 'node:https';
import http from 'node:http';
import {readFileSync} from 'node:fs';
https.createServer({key:readFileSync('artifacts/n1-tls/server.key'),cert:readFileSync('artifacts/n1-tls/server.pem')}, (request,response) => {
  const upstream = http.request({hostname:'127.0.0.1',port:44020,path:request.url,method:request.method,headers:request.headers}, result => {
    response.writeHead(result.statusCode ?? 502,result.headers); result.pipe(response);
  });
  upstream.on('error', () => {response.writeHead(502);response.end();});
  request.pipe(upstream);
}).listen(44021,'127.0.0.1', () => console.log('N1 TLS tunnel ready'));
