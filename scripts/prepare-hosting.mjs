import {mkdirSync, cpSync, rmSync, readdirSync, readFileSync, writeFileSync, existsSync, renameSync} from 'node:fs';
import {resolve, extname} from 'node:path';

const root = resolve(import.meta.dirname, '..'), dist = resolve(root, 'dist');

const htmlFiles = () => readdirSync(dist).filter(file => extname(file) === '.html');

function normalizeHtmlReferences() {
  for (const htmlFile of htmlFiles()) {
    const htmlPath = resolve(dist, htmlFile);
    const content = readFileSync(htmlPath, 'utf8');
    const updated = content.replace(/\b(href|src)="\.\/([^"?#]+)([?#][^"]*)?"/g, '$1="$2$3"');
    if (updated !== content) writeFileSync(htmlPath, updated, 'utf8');
  }
}

function normalizeProductionJavaScript() {
  for (const entry of readdirSync(dist, {withFileTypes: true})) {
    if (!entry.isFile() || extname(entry.name) !== '.js') continue;
    const scriptPath = resolve(dist, entry.name);
    const content = readFileSync(scriptPath, 'utf8');
    const updated = content.replace(/(['"`])\/([A-Za-z0-9_-]+\.html)(?=[?#'"`])/g, '$1$2');
    if (updated !== content) writeFileSync(scriptPath, updated, 'utf8');
  }
}

function verifyProductionReferences() {
  const invalidReference = /\b(?:href|src)="(?:\.?\.\/|\/)(?:css|js|assets|images|pages)\//;
  const invalidEnvironment = /(?:localhost|127\.0\.0\.1|file:\/\/\/|\b[A-Za-z]:[\\/])/i;

  for (const htmlFile of htmlFiles()) {
    const content = readFileSync(resolve(dist, htmlFile), 'utf8');
    if (invalidReference.test(content) || invalidEnvironment.test(content)) {
      throw new Error(`Invalid production reference found in ${htmlFile}`);
    }

    for (const match of content.matchAll(/\b(?:href|src)="([^"?#]+)(?:[?#][^"]*)?"/g)) {
      const reference = match[1];
      if (!reference.includes('://') && !reference.startsWith('#') && !existsSync(resolve(dist, reference))) {
        throw new Error(`Missing production file ${reference} referenced by ${htmlFile}`);
      }
    }
  }
}

// ── Step 1: Rename the JS bundle to app.js in dist/ ──────────────────────────
// Rollup may name it app.js, app1.js, app13.js etc. to avoid collisions.
// Since all HTML pages share ONE bundle, rename the single JS file to app.js.
const distFiles = readdirSync(dist, {withFileTypes: true});
const jsBundles = distFiles.filter(e => e.isFile() && extname(e.name) === '.js' && e.name.startsWith('app'));
if (jsBundles.length === 1 && jsBundles[0].name !== 'app.js') {
  const oldName = jsBundles[0].name;
  renameSync(resolve(dist, oldName), resolve(dist, 'app.js'));
  // Update all HTML files in dist/ to reference app.js instead of old name
  readdirSync(dist).filter(f => extname(f) === '.html').forEach(htmlFile => {
    const htmlPath = resolve(dist, htmlFile);
    const content = readFileSync(htmlPath, 'utf8');
    const updated = content.replaceAll(oldName, 'app.js');
    if (updated !== content) writeFileSync(htmlPath, updated, 'utf8');
  });
  console.log(` OK  Renamed ${oldName} → app.js and updated HTML references`);
}

normalizeHtmlReferences();
normalizeProductionJavaScript();
verifyProductionReferences();

// ── Step 2: Build deploy/ (Apache / cPanel / traditional shared hosting) ─────
// All files flat at root: app.js, global.css, favicon.svg beside each HTML.
const deploy = resolve(root, 'deploy');
if (existsSync(deploy)) rmSync(deploy, {recursive: true, force: true});
mkdirSync(deploy, {recursive: true});

// Copy every root-level file from dist/ (HTML, app.js, global.css, favicon.svg, etc.)
readdirSync(dist, {withFileTypes: true}).forEach(entry => {
  if (entry.isFile()) {
    cpSync(resolve(dist, entry.name), resolve(deploy, entry.name));
  }
  // Skip sub-directories (server/ etc.)
});

// Ensure favicon.svg is present (from project root if not produced by Vite)
if (!existsSync(resolve(deploy, 'favicon.svg'))) {
  const srcFavicon = resolve(root, 'favicon.svg');
  if (existsSync(srcFavicon)) cpSync(srcFavicon, resolve(deploy, 'favicon.svg'));
}

// ── Step 3: Write .htaccess for Apache/cPanel servers ────────────────────────
const htaccess = `# EVENTX - Apache configuration for static hosting
Options -Indexes

# Redirect /favicon.ico to the SVG favicon
RedirectMatch 302 ^/favicon\\.ico$ /favicon.svg

# Serve correct MIME types
AddType image/svg+xml .svg
AddType application/javascript .js

# Enable CORS for assets (required for ES modules with crossorigin attribute)
<FilesMatch "\\.(js|css|svg)$">
  Header set Access-Control-Allow-Origin "*"
</FilesMatch>

# Cache static assets
<FilesMatch "\\.(js|css)$">
  Header set Cache-Control "public, max-age=86400"
</FilesMatch>
`;
writeFileSync(resolve(deploy, '.htaccess'), htaccess);

// ── Step 4: Cloudflare Workers entry (optional CF deployment) ─────────────────
mkdirSync(resolve(dist, 'server'), {recursive: true});
const workerCode = `export default {async fetch(request,env){const url=new URL(request.url);if(url.pathname==='/favicon.ico'){url.pathname='/favicon.svg';return env.ASSETS.fetch(new Request(url,request))}if(url.pathname==='/'||url.pathname==='/index.html')url.pathname='/eventx.html';return env.ASSETS.fetch(new Request(url,request))}};
`;
writeFileSync(resolve(dist, 'server', 'index.js'), workerCode);

// ── Report ─────────────────────────────────────────────────────────────────────
const deployedHtmlFiles = readdirSync(deploy).filter(f => extname(f) === '.html').sort();
const assetFiles = readdirSync(deploy).filter(f => extname(f) !== '.html' && f !== '.htaccess').sort();
console.log('\n OK  Production build complete');
console.log(` OK  ${deployedHtmlFiles.length} HTML pages — all at root, filename-only references`);
console.log(` OK  Shared assets: ${assetFiles.join(', ')}`);
console.log('\n DEPLOY: Upload CONTENTS of deploy/ to your server web root.\n');
console.log('   File structure at rut.kpriet.ac.in/:');
[...deployedHtmlFiles, ...assetFiles, '.htaccess'].sort().forEach(f => console.log(`     ${f}`));
console.log('');
