// Scoped startup repairs for the exported, single-threaded Godot runtime.
// No rendering, scene, mesh, texture, or gameplay settings are changed here.
export function patchEngine(source) {
  let engine = source;
  function replace(oldText, newText) {
    if (!engine.includes(oldText) || engine.indexOf(oldText) !== engine.lastIndexOf(oldText)) {
      throw new Error(`Godot export changed: ${oldText.slice(0, 90)}`);
    }
    engine = engine.replace(oldText, newText);
  }
  replace('return fetch(file).then(function (response)',
    'return (globalThis.toyroomAssetFetch || fetch)(file).then(function (response)');
  const trackerStart = engine.indexOf('\tfunction getTrackedResponse(response, load_status) {');
  const trackerEnd = engine.indexOf('\n\tfunction loadFetch(', trackerStart);
  if (trackerStart < 0 || trackerEnd < 0) throw new Error('Godot tracker changed');
  engine = engine.slice(0, trackerStart) + `
  function getTrackedResponse(response, load_status) {
    const reader = response.body.getReader();
    return new Response(new ReadableStream({
      async pull(controller) {
        try {
          const result = await reader.read();
          if (result.done) { load_status.done = true; controller.close(); }
          else { load_status.loaded += result.value.length; controller.enqueue(result.value); }
        } catch (error) { load_status.done = true; controller.error(error); }
      },
      cancel(reason) { return reader.cancel(reason); }
    }), { headers: response.headers });
  }
` + engine.slice(trackerEnd);
  replace('return tr.arrayBuffer();', 'return globalThis.toyroomReadBuffer ? globalThis.toyroomReadBuffer(tr, fileSize) : tr.arrayBuffer();');
  // Transport already retries individual chunks. Never allocate/decode the entire
  // 407 MiB pack four times after a deterministic memory or decoding error.
  replace('fileSize, raw), DOWNLOAD_ATTEMPTS_MAX);', 'fileSize, raw), globalThis.toyroomAssetFetch ? 1 : DOWNLOAD_ATTEMPTS_MAX);');
  // Only preloaded, relinquished buffers may transfer ownership. Public copyToFS
  // retains its original copy semantics for caller-owned mutable buffers.
  replace('copy_to_fs:function(path,buffer){', 'copy_to_fs:function(path,buffer,takeOwnership=false){');
  replace('FS.writeFile(path,new Uint8Array(buffer))', 'FS.writeFile(path,new Uint8Array(buffer),{canOwn:takeOwnership})');
  replace("me.rtenv['copyToFS'](file.path, file.buffer);", "me.rtenv['copyToFS'](file.path, file.buffer, true);");
  // The stock custom-instantiation adapter has no rejection path.
  replace('return new Promise(resolve=>{instantiateWasm(info,inst=>resolve(receiveInstance(inst)))})',
    'return new Promise((resolve,reject)=>{try{Promise.resolve(instantiateWasm(info,inst=>{try{resolve(receiveInstance(inst))}catch(e){reject(e)}})).catch(reject)}catch(e){reject(e)}})');
  const instantiateStart = engine.indexOf("\t\t\t'instantiateWasm': function (imports, onSuccess) {");
  const instantiateEnd = engine.indexOf("\n\t\t\t'locateFile':", instantiateStart);
  if (instantiateStart < 0 || instantiateEnd < 0) throw new Error('Godot module config changed');
  // Byte instantiation also works on browsers whose streaming API exists but
  // rejects custom decoded Responses. There is no unread Response.clone branch.
  engine = engine.slice(0, instantiateStart) + `
      'onAbort': function (reason) { globalThis.toyroomFatal?.(new Error(String(reason))); },
      'instantiateWasm': async function (imports, onSuccess) {
        const response = r; r = null;
        let buffer = await (globalThis.toyroomReadBuffer ? globalThis.toyroomReadBuffer(response) : response.arrayBuffer());
        globalThis.toyroomStartup?.({phase:'compile'});
        try {
          const result = await WebAssembly.instantiate(buffer, imports);
          onSuccess(result.instance, result.module);
        } catch (error) { error.toyroomStage = 'compile'; throw error; }
        finally { buffer = null; }
      },` + engine.slice(instantiateEnd);
  const initStart = engine.indexOf('\t\t\t\tfunction doInit(promise) {');
  const initEnd = engine.indexOf('\n\t\t\t\tpreloader.setProgressFunc', initStart);
  if (initStart < 0 || initEnd < 0) throw new Error('Godot init changed');
  engine = engine.slice(0, initStart) + `
        function doInit(promise) {
          return promise.then(response => Godot(me.config.getModuleConfig(loadPath, response))).then(async module => {
            globalThis.toyroomStartup?.({phase:'storage'});
            let timer;
            try {
              await Promise.race([module['initFS'](me.config.persistentPaths), new Promise((_,reject) => {
                timer = setTimeout(() => { const error = new Error('浏览器存档存储未响应'); error.toyroomStage='storage'; reject(error); },15000);
              })]);
            } finally { clearTimeout(timer); }
            me.rtenv = module;
            if (me.config.unloadAfterInit) Engine.unload();
          });
        }` + engine.slice(initEnd);
  replace("\t\t\t\t\t\tfor (const file of preloader.preloadedFiles) {", "\t\t\t\t\t\tglobalThis.toyroomStartup?.({phase:'mount'});\n\t\t\t\t\t\tfor (const file of preloader.preloadedFiles) {");
  replace("me.rtenv['callMain'](me.config.args);", "globalThis.toyroomStartup?.({phase:'scene'});\n\t\t\t\t\t\tme.rtenv['callMain'](me.config.args);");
  return engine;
}
