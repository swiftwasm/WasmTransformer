input=$1
output=$2

if [[ -z "${SWIFT_TOOLCHAIN}" ]]; then
  echo "ERROR: Please set SWIFT_TOOLCHAIN env variable"
  exit 1
fi

SWIFTC=$SWIFT_TOOLCHAIN/bin/swiftc
"$SWIFTC" -target wasm32-unknown-wasi \
  -sdk "$SWIFT_TOOLCHAIN/share/wasi-sysroot" \
  -I "$SWIFT_TOOLCHAIN/lib/swift/wasi/wasm32" \
  -lFoundation \
  -lCoreFoundation \
  -lBlocksRuntime \
  -licui18n \
  -luuid \
  "$input" -o "$output"
