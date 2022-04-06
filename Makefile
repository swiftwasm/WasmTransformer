update-fixture: Sources/WasmTransformer/Transformers/StackOverflowSanitizer+Fixtures.swift

Fixtures/build/stack_sanitizer_support.o:
	$(MAKE) -C Fixtures build/stack_sanitizer_support.o
Sources/WasmTransformer/Transformers/StackOverflowSanitizer+Fixtures.swift: Fixtures/build/stack_sanitizer_support.o Tools/GenerateStackOverflowSanitizerSupport.swift
	swift ./Tools/GenerateStackOverflowSanitizerSupport.swift Fixtures/build/stack_sanitizer_support.o > Sources/WasmTransformer/Transformers/StackOverflowSanitizer+Fixtures.swift
