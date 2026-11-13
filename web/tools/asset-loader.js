/* Bounded, resumable transport shared by desktop and touch entry points. */
(() => {
  class ToyroomAssets {
    constructor(manifest, onProgress = () => {}) {
      this.manifest = manifest;
      this.onProgress = onProgress;
      this.fetch = globalThis.fetch.bind(globalThis);
      this.total = Object.values(manifest).reduce((n, a) => n + a.bytes, 0);
      this.loaded = new Map();
      this.active = 0;
      this.waiters = [];
      this.cache = this.openCache();
    }
    async limited(work) {
      if (this.active >= 3) await new Promise(resolve => this.waiters.push(resolve));
      else this.active++;
      try { return await work(); }
      finally {
        const next = this.waiters.shift();
        if (next) next(); else this.active--;
      }
    }
    async deadline(promise, ms = 2500) {
      let timer;
      try { return await Promise.race([promise, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("Storage timeout")), ms);
      })]); } finally { clearTimeout(timer); }
    }
    async openCache() {
      try { return globalThis.caches ? await this.deadline(caches.open("toyroom-assets-v1")) : null; }
      catch (_) { return null; }
    }
    track(part, bytes, cached = false) {
      this.loaded.set(part.path, Math.min(part.bytes, bytes));
      const loaded = [...this.loaded.values()].reduce((a, b) => a + b, 0);
      this.onProgress({ loaded, total: this.total, cached });
    }
    async allCached() {
      const cache = await this.cache;
      if (!cache) return false;
      try {
        const parts = Object.values(this.manifest).flatMap(a => a.parts);
        const found = await this.deadline(Promise.all(parts.map(p => cache.match(p.path))));
        return found.every((r, i) => r && Number(r.headers.get("Content-Length")) === parts[i].bytes);
      } catch (_) { return false; }
    }
    async prune() {
      const cache = await this.cache;
      if (!cache) return;
      try {
        const wanted = new Set(Object.values(this.manifest).flatMap(a => a.parts.map(p => new URL(p.path, location.href).href)));
        const keys = await this.deadline(cache.keys());
        await this.deadline(Promise.all(keys.filter(k => !wanted.has(k.url)).map(k => cache.delete(k))));
      } catch (_) { /* Storage is optional, including on private browser tabs. */ }
    }
    async chunk(part, group) {
      return this.limited(async () => {
        if (group.cancelled) throw new Error("下载已取消");
        const cache = await this.cache;
        if (cache) {
          try {
            const saved = await this.deadline(cache.match(part.path));
            if (saved) {
              const bytes = new Uint8Array(await this.deadline(saved.arrayBuffer()));
              if (bytes.length === part.bytes) { this.track(part, bytes.length, true); return bytes; }
              await this.deadline(cache.delete(part.path));
            }
          } catch (_) { /* A broken/denied cache must not prevent playing. */ }
        }
        for (let attempt = 0; attempt < 3; attempt++) {
          if (group.cancelled) throw new Error("下载已取消");
          const abort = typeof AbortController === "function" ? new AbortController() : null;
          let timeout, reader, rejectStalled;
          const stalled = new Promise((_, reject) => { rejectStalled = reject; });
          const stop = () => { abort?.abort(); reader?.cancel().catch(() => {}); rejectStalled(new Error("下载已取消")); };
          group.stops.add(stop);
          const heartbeat = () => {
            clearTimeout(timeout);
            timeout = setTimeout(() => { abort?.abort(); rejectStalled(new Error("下载连接无响应")); }, 45000);
          };
          try {
            heartbeat();
            const response = await Promise.race([this.fetch(part.path, abort ? { signal: abort.signal } : {}), stalled]);
            if (!response.ok) throw new Error(`资源请求失败 (${response.status})`);
            // Preallocate one small part, avoiding Response.arrayBuffer's extra whole-part copy.
            let bytes;
            if (response.body?.getReader) {
              bytes = new Uint8Array(part.bytes);
              reader = response.body.getReader();
              let offset = 0;
              while (true) {
                const { value, done } = await Promise.race([reader.read(), stalled]);
                if (done) break;
                if (offset + value.length > bytes.length) throw new Error("下载资源长度错误");
                bytes.set(value, offset); offset += value.length;
                heartbeat(); this.track(part, offset);
              }
              if (offset !== part.bytes) throw new Error("下载资源不完整");
            } else {
              bytes = new Uint8Array(await Promise.race([response.arrayBuffer(), stalled]));
              if (bytes.length !== part.bytes) throw new Error("下载资源不完整");
            }
            clearTimeout(timeout);
            this.track(part, bytes.length);
            if (cache) {
              try { await this.deadline(cache.put(part.path, new Response(bytes, { headers: {
                "Content-Type": "application/octet-stream", "Content-Length": String(bytes.length),
              } }))); } catch (_) { /* Continue when storage is full or unavailable. */ }
            }
            return bytes;
          } catch (error) {
            abort?.abort(); reader?.cancel().catch(() => {});
            if (group.cancelled) throw error;
            if (attempt === 2) throw new Error(`${error.message}，已下载的完整部分会保留`);
            await new Promise(resolve => setTimeout(resolve, 350 * (attempt + 1)));
          } finally { clearTimeout(timeout); group.stops.delete(stop); }
        }
      });
    }
    compressedStream(asset) {
      const pending = new Map();
      const group = { cancelled: false, stops: new Set() };
      let index = 0, bytes = null, offset = 0, cancelled = false;
      const cancel = () => {
        cancelled = true; group.cancelled = true; bytes = null; pending.clear();
        for (const stop of group.stops) stop();
      };
      const prefetch = () => {
        for (let i = index; i < Math.min(index + 3, asset.parts.length); i++) {
          if (!pending.has(i)) {
            // Catch immediately, including errors in a prefetched future part.
            pending.set(i, this.chunk(asset.parts[i], group).then(data => ({ data }), error => ({ error })));
          }
        }
      };
      return new ReadableStream({
        pull: async controller => {
          try {
            if (cancelled) return;
            if (!bytes) {
              if (index >= asset.parts.length) { controller.close(); return; }
              prefetch();
              const result = await pending.get(index);
              if (cancelled) return;
              if (result.error) throw result.error;
              bytes = result.data; offset = 0;
            }
            const end = Math.min(offset + 65536, bytes.length);
            controller.enqueue(bytes.subarray(offset, end)); offset = end;
            if (offset === bytes.length) { pending.delete(index++); bytes = null; prefetch(); }
          } catch (error) { cancel(); controller.error(error); }
        },
        cancel,
      });
    }
    async response(file) {
      const asset = this.manifest[file];
      if (!asset) return this.fetch(file);
      const compressed = this.compressedStream(asset);
      let unpacked;
      try {
        if (typeof DecompressionStream !== "function") throw new Error("Use portable decompressor");
        unpacked = compressed.pipeThrough(new DecompressionStream("gzip"));
      } catch (_) {
        if (!globalThis.fflate?.Gunzip) throw new Error("解压组件没有加载，请重试");
        const reader = compressed.getReader();
        let decoder, ended = false, produced = false;
        unpacked = new ReadableStream({
          start(controller) {
            decoder = new fflate.Gunzip((data, final) => {
              if (data.length) { produced = true; controller.enqueue(data); }
              if (final) controller.close();
            });
          },
          async pull(controller) {
            if (ended) return;
            try {
              produced = false;
              do {
                const { value, done } = await reader.read();
                ended = done; decoder.push(value || new Uint8Array(0), done);
              } while (!produced && !ended);
            } catch (error) { ended = true; controller.error(error); reader.cancel().catch(() => {}); }
          },
          cancel(reason) { ended = true; return reader.cancel(reason); },
        });
      }
      return new Response(unpacked, { headers: { "Content-Type": asset.type, "Content-Length": String(asset.originalBytes) } });
    }
  }
  // Avoid building a second 400+ MB copy inside the browser's response accumulator.
  async function toyroomReadBuffer(response, expected) {
    const size = Number(expected || response.headers.get("Content-Length"));
    if (!size || !response.body?.getReader) return response.arrayBuffer();
    const bytes = new Uint8Array(size), reader = response.body.getReader();
    let offset = 0;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (offset + value.length > size) throw new Error("解压资源长度错误");
        bytes.set(value, offset); offset += value.length;
      }
      if (offset !== size) throw new Error("解压资源不完整");
      return bytes.buffer;
    } catch (error) { reader.cancel().catch(() => {}); throw error; }
  }
  globalThis.ToyroomAssets = ToyroomAssets;
  globalThis.toyroomReadBuffer = toyroomReadBuffer;
})();
