ifndef SWIFT_TOOLCHAIN
  $(error Please set SWIFT_TOOLCHAIN env variable)
endif

SWIFTC = ${SWIFT_TOOLCHAIN}/bin/swiftc
CLANG = ${SWIFT_TOOLCHAIN}/bin/clang
LLVM_AR = ${SWIFT_TOOLCHAIN}/bin/llvm-ar

.PHONY: all
all: build/I64ImportTransformerTests.wasm build/StackOverflowSanitizerTests.wasm

build/%.wasm: Entrypoints/%.swift
	$(SWIFTC) -target wasm32-unknown-wasi \
	  -sdk "${SWIFT_TOOLCHAIN}/share/wasi-sysroot" \
	  -I "${SWIFT_TOOLCHAIN}/lib/swift/wasi/wasm32" \
	  -lFoundation \
	  -lCoreFoundation \
	  -lBlocksRuntime \
	  -licui18n \
	  -luuid \
	  $< -o $@

build/StackOverflowSanitizerTests.wasm: Entrypoints/StackOverflowSanitizerTests.swift build/stack_sanitizer_support.o
	$(SWIFTC) -target wasm32-unknown-wasi \
	  -sdk "${SWIFT_TOOLCHAIN}/share/wasi-sysroot" \
	  -I "${SWIFT_TOOLCHAIN}/lib/swift/wasi/wasm32" \
	  -lFoundation \
	  -lCoreFoundation \
	  -lBlocksRuntime \
	  -licui18n \
	  -luuid \
	  build/stack_sanitizer_support.o \
	  $< -o $@

build/stack_sanitizer_support.o: stack_sanitizer_support.c
	$(CLANG) -c -target wasm32-unknown-wasi $< \
	  -o build/stack_sanitizer_support.o
