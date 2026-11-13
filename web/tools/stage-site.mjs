import { createReadStream, createWriteStream } from "node:fs";
import { copyFile, mkdir, readFile, readdir, stat, unlink, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve, join } from "node:path";
import { pipeline } from "node:stream/promises";
import { createGzip } from "node:zlib";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const build = join(root, "web-build");
const tools = join(root, "tools");
const dist = process.env.TOYROOM_STAGE_DIST ? resolve(process.env.TOYROOM_STAGE_DIST) : join(root, "site", "dist");
const payload = join(dist, "payload");
await mkdir(payload, { recursive: true });
const packSource = process.argv[2] ? resolve(process.argv[2]) : join(build, "index.pck");
const chunkLimit = 16 * 1024 * 1024;

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

const resources = {
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
const engine = await readFile(join(build, "index.js"), "utf8");
const loader = "return fetch(file).then(function (response)";
if (!engine.includes(loader)) throw new Error("Godot loader changed");
await writeFile(join(dist, "index.js"), engine.replace(loader, "return (globalThis.toyroomAssetFetch || fetch)(file).then(function (response)"));
await writeFile(join(dist, "payload.js"), `globalThis.TOYROOM_PAYLOAD = ${JSON.stringify(resources)};\n`);
await copyFile(join(tools, "web-shell.html"), join(dist, "index.html"));
await copyFile(join(tools, "shell.css"), join(dist, "shell.css"));
await copyFile(join(tools, "boot.js"), join(dist, "boot.js"));
await copyFile(join(tools, "touch.js"), join(dist, "touch.js"));
await copyFile(join(tools, "NotoSansSC-OFL.txt"), join(dist, "font-license.txt"));
console.log(JSON.stringify(Object.fromEntries(Object.entries(resources).map(([file, { bytes, originalBytes, parts }]) => [file, { bytes, originalBytes, chunks: parts.length }]))));
