import { WASI } from "@wasmer/wasi";
import { WasmFs } from "@wasmer/wasmfs";

window.I64ImportTransformerTests = async (bytes) => {
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

window.StackOverflowSanitizerTests = async (bytes) => {
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
    __stack_sanitizer: {
      report_stack_overflow: () => {
        throw new Error("CATCH_STACK_OVERFLOW");
      }
    }
  };

  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, importObject);
  wasi.start(instance);
}
