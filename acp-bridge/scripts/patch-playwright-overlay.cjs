#!/usr/bin/env node
/**
 * Patches Playwright MCP's extensionContextFactory.js to inject the Fazm
 * browser overlay on every page load when running in extension mode.
 *
 * addInitScript() does NOT work on CDP-connected contexts, so we use
 * page 'load' / 'domcontentloaded' event listeners instead.
 *
 * Run automatically via npm postinstall.
 */
const fs = require("fs");
const path = require("path");

const targetFile = path.join(
  __dirname,
  "..",
  "node_modules",
  "playwright",
  "lib",
  "mcp",
  "extension",
  "extensionContextFactory.js"
);

if (!fs.existsSync(targetFile)) {
  console.log("[patch-overlay] extensionContextFactory.js not found, skipping");
  process.exit(0);
}

let code = fs.readFileSync(targetFile, "utf-8");

// Already patched?
if (code.includes("_fazmOverlayScript")) {
  console.log("[patch-overlay] Already patched, skipping");
  process.exit(0);
}

// Insert requires for path and fs after cdpRelay require
if (!code.includes('require("path")')) {
  code = code.replace(
    'var import_cdpRelay = require("./cdpRelay");',
    'var import_cdpRelay = require("./cdpRelay");\nvar import_path = require("path");\nvar import_fs = require("fs");'
  );
}

// Insert overlay loader after debugLogger line
const overlayLoader = `
// Fazm: load overlay init script for browser injection
let _fazmOverlayScript = null;
try {
  const overlayPath = import_path.join(__dirname, "..", "..", "..", "..", "..", "browser-overlay-init.js");
  if (import_fs.existsSync(overlayPath)) {
    _fazmOverlayScript = import_fs.readFileSync(overlayPath, "utf-8");
  }
} catch (e) {
  // Overlay is optional
}
`;

code = code.replace(
  'const debugLogger = (0, import_utilsBundle.debug)("pw:mcp:relay");',
  'const debugLogger = (0, import_utilsBundle.debug)("pw:mcp:relay");\n' + overlayLoader
);

// Patch createContext: the original returns browser.contexts()[0] inline.
// We need to extract it to a variable so we can set up event listeners.
code = code.replace(
  `async createContext(clientInfo, abortSignal, options) {
    const browser = await this._obtainBrowser(clientInfo, abortSignal, options?.toolName);
    return {
      browserContext: browser.contexts()[0],`,
  `async createContext(clientInfo, abortSignal, options) {
    const browser = await this._obtainBrowser(clientInfo, abortSignal, options?.toolName);
    const browserContext = browser.contexts()[0];
    // Fazm: inject overlay on every page load via event listeners
    // addInitScript does NOT work on CDP-connected contexts, so we use page events
    if (_fazmOverlayScript && browserContext) {
      const _injectOverlay = async (p) => { try { await p.evaluate(_fazmOverlayScript); } catch (e) {} };
      const _setupPage = (p) => { p.on("load", () => _injectOverlay(p)); p.on("domcontentloaded", () => _injectOverlay(p)); };
      for (const p of browserContext.pages()) _setupPage(p);
      browserContext.on("page", (p) => _setupPage(p));
    }
    return {
      browserContext,`
);

fs.writeFileSync(targetFile, code);
console.log("[patch-overlay] Successfully patched extensionContextFactory.js");
