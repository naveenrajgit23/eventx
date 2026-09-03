import {defineConfig} from 'vite';import {resolve} from 'node:path';import {readdirSync} from 'node:fs';import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('.',import.meta.url));const pages=Object.fromEntries(readdirSync(resolve(root,'pages')).filter(x=>x.endsWith('.html')).map(x=>[x.replace('.html',''),resolve(root,'pages',x)]));
export default defineConfig({build:{rollupOptions:{input:{main:resolve(root,'index.html'),...pages}}}})
