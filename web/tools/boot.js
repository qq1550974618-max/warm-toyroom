(() => {
  const canvas = document.querySelector("#game");
  const intro = document.querySelector("#intro");
  const status = document.querySelector("#status");
  const progress = document.querySelector("#progress");
  const actions = document.querySelector(".actions");
  const play = document.querySelector("#play");
  const mobile = document.querySelector("#mobile");
  const look = document.querySelector("#look");
  window.toyroomFullscreen = async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if (document.documentElement.requestFullscreen) await document.documentElement.requestFullscreen();
      else if (document.documentElement.webkitRequestFullscreen) document.documentElement.webkitRequestFullscreen();
      else document.body.classList.toggle("expanded");
    } catch (_) { document.body.classList.toggle("expanded"); }
    canvas.focus({preventScroll:true});
  };
  document.querySelector("#fullscreen").onclick = window.toyroomFullscreen;
  document.addEventListener("fullscreenchange", () => {
    document.querySelector("#fullscreen").textContent = document.fullscreenElement ? "退出全屏" : "全屏";
  });
  const resources = globalThis.TOYROOM_PAYLOAD;
  const nativeFetch = window.fetch.bind(window);
  const transportBytes = Object.values(resources).reduce((sum, entry) => sum + entry.bytes, 0);
  const bytesByChunk = new Map();
  const cachedChunks = new Set();
  const cacheName = "toyroom-assets-v1";
  const cachePromise = (async () => {
    try {
      if (!globalThis.caches) return null;
      const cache = await caches.open(cacheName);
      const wanted = new Set(Object.values(resources).flatMap(asset => asset.parts.map(part => new URL(part.path, location.href).href)));
      for (const key of await cache.keys()) if (!wanted.has(key.url)) await cache.delete(key);
      return cache;
    } catch (_) { return null; }
  })();
  const mib = bytes => (bytes / (1024 * 1024)).toFixed(1);
  let ready = false;
  let hasLocked = false;
  let failed = false;
  let mobileMode = false;
  let renderHeight = 720;

  window.setToyroomRenderHeight = height => {
    if (![540, 720, 1080].includes(height)) return;
    renderHeight = height;
    requestAnimationFrame(() => {
      const width = Math.round(renderHeight * 16 / 9);
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== renderHeight) canvas.height = renderHeight;
    });
  };

  document.addEventListener("pointerlockchange", () => {
    if (document.pointerLockElement === canvas) hasLocked = true;
    look.hidden = !ready || hasLocked || mobileMode;
  });

  function setReady() {
    if (ready || failed) return;
    ready = true;
    window.setToyroomRenderHeight(renderHeight);
    intro.hidden = true;
    look.hidden = hasLocked || mobileMode;
    if (mobileMode) window.activateToyroomTouch();
    canvas.focus({ preventScroll: true });
  }

  function showError(error) {
    if (failed) return;
    failed = true;
    console.error(error);
    progress.hidden = true;
    status.textContent = "试玩加载中断。请检查网络后重新加载。";
    play.textContent = "重新加载";
    play.onclick = () => location.reload();
    mobile.hidden = true;
    actions.hidden = false;
  }

  function track(part, bytes) {
    bytesByChunk.set(part, bytes);
    const loaded = [...bytesByChunk.values()].reduce((sum, count) => sum + count, 0);
    progress.value = loaded / transportBytes * 100;
    status.textContent = loaded >= transportBytes
      ? "正在准备房间和玩具…"
      : `${cachedChunks.has(part) ? "正在读取本机游戏" : "正在下载并保存游戏"} · ${mib(loaded)} / ${mib(transportBytes)} MiB`;
  }

  async function loadChunk(part) {
    const cache = await cachePromise;
    if (cache) {
      try {
        const saved = await cache.match(part.path);
        if (saved) {
          const bytes = await saved.arrayBuffer();
          if (bytes.byteLength === part.bytes) {
            cachedChunks.add(part.path);
            return new Response(bytes).body.getReader();
          }
          await cache.delete(part.path);
        }
      } catch (_) { /* Storage may be denied; network loading remains available. */ }
    }
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const response = await nativeFetch(part.path, { signal: AbortSignal.timeout(120000) });
        if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
        // Only keep one compressed chunk in memory. Never buffer the entire game
        // for caching, and never let a failed cache write prevent game startup.
        const bytes = await response.arrayBuffer();
        if (bytes.byteLength !== part.bytes) throw new Error(`Incomplete asset: ${part.path}`);
        if (cache) {
          try {
            await cache.put(part.path, new Response(bytes, { headers: {
              "Content-Type": "application/octet-stream", "Content-Length": String(bytes.byteLength),
            } }));
          } catch (_) { /* Quota/private mode: continue playing with this chunk. */ }
        }
        return new Response(bytes).body.getReader();
      } catch (error) {
        if (attempt === 2) throw error;
        await new Promise(resolve => setTimeout(resolve, 600 * (attempt + 1)));
      }
    }
  }

  window.toyroomAssetFetch = async file => {
    const resource = resources[file];
    if (!resource) return nativeFetch(file);
    let index = 0;
    let part = resource.parts[index];
    let reader;
    let seen = 0;
    const compressed = new ReadableStream({
      async pull(controller) {
        try {
          while (part) {
            if (!reader) reader = await loadChunk(part);
            const { done, value } = await reader.read();
            if (!done) {
              seen += value.byteLength;
              track(part.path, seen);
              controller.enqueue(value);
              return;
            }
            if (seen !== part.bytes) throw new Error(`Incomplete asset: ${part.path}`);
            reader = null;
            seen = 0;
            part = resource.parts[++index];
          }
          controller.close();
        } catch (error) {
          showError(error);
          controller.error(error);
        }
      },
      cancel(reason) { return reader?.cancel(reason); },
    });
    return new Response(compressed.pipeThrough(new DecompressionStream("gzip")), {
      headers: { "Content-Type": resource.type, "Content-Length": String(resource.originalBytes) },
    });
  };

  async function start(height, qualityArg) {
    mobileMode = qualityArg === "--web-mobile";
    actions.hidden = true;
    progress.hidden = false;
    status.textContent = "正在连接游戏资源…";
    if (navigator.storage?.persist) navigator.storage.persist().catch(() => {});
    canvas.width = Math.round(height * 16 / 9);
    canvas.height = height;
    renderHeight = height;
    const args = ["--resolution", `${canvas.width}x${height}`];
    if (qualityArg) args.push("--");
    if (qualityArg) args.push(qualityArg);
    const engine = new Engine({
      executable: "index",
      mainPack: "index.pck",
      canvas,
      canvasResizePolicy: 0,
      focusCanvas: true,
      args,
      fileSizes: Object.fromEntries(Object.entries(resources).map(([file, asset]) => [file, asset.originalBytes])),
      onPrint(message) {
        console.info(message);
        if (message.startsWith("ROOM_READY")) setTimeout(setReady, 0);
      },
      onPrintError(message) {
        console.error(message);
      },
    });
    try {
      await engine.startGame();
    } catch (error) {
      showError(error);
    }
  }

  const missing = Engine.getMissingFeatures({ threads: false });
  if (missing.length || typeof DecompressionStream === "undefined") {
    status.textContent = "此浏览器无法运行试玩。请使用支持 WebGL 2 的新版 Chrome、Edge 或 Firefox。";
    actions.hidden = true;
  } else {
    status.textContent = `首次载入约 ${mib(transportBytes)} MiB · 支持键鼠和触屏`;
    cachePromise.then(async cache => {
      if (!cache || actions.hidden) return;
      const parts = Object.values(resources).flatMap(asset => asset.parts);
      const saved = await Promise.all(parts.map(part => cache.match(part.path)));
      if (!actions.hidden && saved.every((response, i) => response && Number(response.headers.get("Content-Length")) === parts[i].bytes)) {
        status.textContent = "游戏已保存在本机 · 本次无需重新下载整包";
      }
    }).catch(() => {});
    play.onclick = () => start(720);
    mobile.onclick = () => start(720, "--web-mobile");
  }
})();
