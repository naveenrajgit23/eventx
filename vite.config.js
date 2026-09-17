import {defineConfig} from 'vite';
import {resolve} from 'node:path';
import {readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));

// Discover all HTML files directly in the root directory (and pages/ if it exists)
const rootHtmlFiles = readdirSync(root).filter(x => x.endsWith('.html'));
const htmlEntries = Object.fromEntries(
  rootHtmlFiles.map(x => [x.replace('.html', ''), resolve(root, x)])
);

const productionEntries = {
  ...htmlEntries
};

export default defineConfig(({ command }) => ({
  // During dev: absolute paths (/css/global.css etc.) work via Vite's dev server.
  // During build: relative paths (app.js, global.css) so each HTML page can be
  // opened directly from any directory on the hosting server without a base path.
  base: command === 'build' ? './' : '/',

  appType: 'mpa',

  plugins: [
    {
      name: 'rewrite-root-to-eventx',
      configureServer(server) {
        server.middlewares.use((req, res, next) => {
          if (req.url === '/' || req.url === '/index.html') {
            req.url = '/eventx.html';
          }
          next();
        });
      }
    }
  ],

  build: {
    // Place ALL output files at the dist root — no /assets/ subfolder.
    // This way HTML references are just:  app.js  global.css  favicon.svg
    assetsDir: '',

    rollupOptions: {
      input: productionEntries,
      output: {
        // Single bundled app JS → app.js
        // (app.js is compiled as a shared chunk across all HTML entry points)
        entryFileNames: 'app.js',
        chunkFileNames: 'app.js',
        // CSS → global.css, SVG/other assets keep their original name
        assetFileNames: (assetInfo) => {
          const name = assetInfo.name ?? '';
          if (name.endsWith('.css')) return 'global.css';
          // favicon.svg and other SVGs keep their original filename
          return name;
        }
      }
    }
  }
}));
