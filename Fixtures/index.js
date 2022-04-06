import { WASI } from "@wasmer/wasi";
import { WasmFs } from "@wasmer/wasmfs";

const wrapWASI = (wasiObject) => {
  for (const key in wasiObject.wasiImport) {
    const func = wasiObject.wasiImport[key]
    wasiObject.wasiImport[key] = function() {
      console.log(`[tracing] WASI.${key}`);
      return Reflect.apply(func, undefined, arguments);
    }
  }
  // PATCH: @wasmer-js/wasi@0.x forgets to call `refreshMemory` in `clock_res_get`,
  // which writes its result to memory view. Without the refresh the memory view,
  // it accesses a detached array buffer if the memory is grown by malloc.
  // But they wasmer team discarded the 0.x codebase at all and replaced it with
  // a new implementation written in Rust. The new version 1.x is really unstable
  // and not production-ready as far as katei investigated in Apr 2022.
  // So override the broken implementation of `clock_res_get` here instead of
  // fixing the wasi polyfill.
  // Reference: https://github.com/wasmerio/wasmer-js/blob/55fa8c17c56348c312a8bd23c69054b1aa633891/packages/wasi/src/index.ts#L557
  const original_clock_res_get = wasiObject.wasiImport["clock_res_get"];
  wasiObject.wasiImport["clock_res_get"] = (clockId, resolution) => {
    wasiObject.refreshMemory();
    return original_clock_res_get(clockId, resolution)
  };
  return wasiObject.wasiImport;
}

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
    wasi_snapshot_preview1: wrapWASI(wasi),
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
    wasi_snapshot_preview1: wrapWASI(wasi),
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
