import { WASI } from "@wasmer/wasi";
import { WasmFs } from "@wasmer/wasmfs";

window.startWasiTask = async (bytes) => {
  const wasmFs = new WasmFs();
  const wasi = new WASI({
    args: [], env: {},
    bindings: {
      ...WASI.defaultBindings,
      fs: wasmFs.fs,
    }
  });

  const importObject = {
    wasi_snapshot_preview1: wasi.wasiImport,
  };

  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, importObject);
  wasi.start(instance);
};
