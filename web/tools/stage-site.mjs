import { createReadStream, createWriteStream } from "node:fs";
import { copyFile, mkdir, readFile, readdir, stat, unlink, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve, join } from "node:path";
import { pipeline } from "node:stream/promises";
import { createGzip } from "node:zlib";
import { fileURLToPath } from "node:url";
import { patchEngine } from './patch-engine.mjs';

const root = fileURLToPath(new URL("../", import.meta.url));
const build = join(root, "web-build");
const tools = join(root, "tools");
const dist = process.env.TOYROOM_STAGE_DIST ? resolve(process.env.TOYROOM_STAGE_DIST) : join(root, "site", "dist");
const payload = join(dist, "payload");
await mkdir(payload, { recursive: true });
const shellOnly = process.argv.includes('--shell-only');
const packArg = process.argv.slice(2).find(a => !a.startsWith('--'));
const packSource = packArg ? resolve(packArg) : join(build, "index.pck");
const chunkLimit = 4 * 1024 * 1024;

async function stage(file, path, type) {
  const compressed = join(build, `${file}.gz`);
  await pipeline(createReadStream(path), createGzip({ level: 6 }), createWriteStream(compressed));
  const hash = createHash("sha256");
  for await (const data of createReadStream(compressed)) hash.update(data);
  const id = hash.digest("hex").slice(0, 12);
  const bytes = (await stat(compressed)).size;
  const originalBytes = (await stat(path)).size;
  const parts = [];
  for (let offset = 0; offset < bytes; offset += chunkLimit) {
    const size = Math.min(bytes - offset, chunkLimit);
    const name = `${file}.${id}.${String(parts.length).padStart(2, "0")}.bin`;
    await pipeline(createReadStream(compressed, { start: offset, end: offset + size - 1 }), createWriteStream(join(payload, name)));
    parts.push({ path: `payload/${name}`, bytes: size });
  }
  return { type, originalBytes, bytes, parts };
}

let resources;
if (shellOnly) {
  const manifest = await readFile(join(dist,'payload.js'),'utf8');
  resources = JSON.parse(manifest.slice(manifest.indexOf('{'),manifest.lastIndexOf('}')+1));
  for (const asset of Object.values(resources)) for (const part of asset.parts) {
    if ((await stat(join(dist,part.path))).size !== part.bytes) throw new Error('Incomplete staged payload');
  }
} else resources = {
  "index.wasm": await stage("index.wasm", join(build, "index.wasm"), "application/wasm"),
  "index.pck": await stage("index.pck", packSource, "application/octet-stream"),
};

const files = new Set(Object.values(resources).flatMap(asset => asset.parts.map(part => part.path)));
for (const name of await readdir(payload)) {
  if (/^index\.(pck|wasm)\.[a-f\d]{12}\.\d+\.bin$/.test(name) && !files.has(`payload/${name}`)) {
    await unlink(join(payload, name));
  }
}

for (const name of await readdir(build)) {
  if (/^index\.audio\..*worklet\.js$/.test(name)) await copyFile(join(build, name), join(dist, name));
}
const engine = patchEngine(await readFile(join(build, "index.js"), "utf8"));
await writeFile(join(dist, "index.js"), engine);
await writeFile(join(dist, "payload.js"), `globalThis.TOYROOM_PAYLOAD = ${JSON.stringify(resources)};\n`);
await copyFile(join(tools, "web-shell.html"), join(dist, "index.html"));
await copyFile(join(tools, "shell.css"), join(dist, "shell.css"));
await copyFile(join(tools, "boot.js"), join(dist, "boot.js"));
await copyFile(join(tools, "touch.js"), join(dist, "touch.js"));
for (const name of ["asset-loader.js", "gzip-worker.js", "touch.css"]) await copyFile(join(tools, name), join(dist, name));
await mkdir(join(dist, "vendor"), { recursive: true });
for (const name of ["fflate-0.8.2.js", "fflate-LICENSE.txt"]) await copyFile(join(tools, "vendor", name), join(dist, "vendor", name));
for (const size of [180,192,512]) await copyFile(join(tools, `icon-${size}.png`), join(dist, `icon-${size}.png`));
await writeFile(join(dist, "manifest.webmanifest"), JSON.stringify({ name: "暖光玩具房", short_name: "玩具房", lang: "zh-CN", start_url: "./", scope: "./", display: "fullscreen", display_override: ["fullscreen", "standalone"], orientation: "landscape", background_color: "#1a120f", theme_color: "#1a120f", icons: [192,512].map(size => ({ src: `icon-${size}.png`, sizes: `${size}x${size}`, type: "image/png", purpose: "any" })) }));
const shellFiles = ["index.html", "index.js", "payload.js", "boot.js", "asset-loader.js", "gzip-worker.js", "touch.js", "shell.css", "touch.css", "vendor/fflate-0.8.2.js", "manifest.webmanifest", "icon-180.png", "icon-192.png", "icon-512.png"];
const shellHash = createHash("sha256");
for (const name of shellFiles) shellHash.update(await readFile(join(dist, name)));
await writeFile(join(dist, "sw.js"), `
const NAME = "toyroom-shell-${shellHash.digest("hex").slice(0, 12)}";
const FILES = ${JSON.stringify(shellFiles)};
self.addEventListener("install", event => event.waitUntil(caches.open(NAME).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener("activate", event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith("toyroom-shell-") && k !== NAME).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", event => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== location.origin || url.pathname.includes("/payload/")) return;
  const relative = url.pathname.slice(new URL(self.registration.scope).pathname.length);
  if (event.request.mode !== "navigate" && !FILES.includes(relative)) return;
  // Online visits always get the published version. Offline can reuse this shell.
  event.respondWith(fetch(event.request).catch(() => caches.open(NAME).then(c => c.match(event.request.mode === "navigate" ? "index.html" : relative)).then(r => r || Response.error())));
});
`);
await copyFile(join(tools, "NotoSansSC-OFL.txt"), join(dist, "font-license.txt"));
console.log(JSON.stringify(Object.fromEntries(Object.entries(resources).map(([file, { bytes, originalBytes, parts }]) => [file, { bytes, originalBytes, chunks: parts.length }]))));
