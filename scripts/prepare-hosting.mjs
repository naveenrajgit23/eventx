import {mkdirSync, cpSync, writeFileSync, existsSync} from 'node:fs';
import {resolve} from 'node:path';

const root = resolve(import.meta.dirname, '..'), dist = resolve(root, 'dist');
mkdirSync(resolve(dist, 'client'), {recursive: true});

for (const name of ['assets', 'pages', 'eventx.html']) {
  const p = resolve(dist, name);
  if (existsSync(p)) {
    cpSync(p, resolve(dist, 'client', name), {recursive: true});
  }
}

mkdirSync(resolve(dist, 'server'), {recursive: true});
writeFileSync(
  resolve(dist, 'server', 'index.js'),
  `export default {async fetch(request,env){const url=new URL(request.url);if(url.pathname==='/favicon.ico')return new Response(null,{status:204});if(url.pathname==='/'||url.pathname==='/index.html')url.pathname='/eventx.html';return env.ASSETS.fetch(new Request(url,request))}};\n`
);
