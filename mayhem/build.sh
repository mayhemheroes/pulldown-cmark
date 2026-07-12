#!/usr/bin/env bash
#
# mayhem/build.sh — build the cargo-fuzz target(s) as sanitized libFuzzer binaries
# (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS) AND the project's own test
# suite (normal flags) so mayhem/test.sh only RUNS it.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem.
# Toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# This first (online) build populates the cargo registry under $CARGO_HOME; the
# offline re-run resolves crates from that cache (the rlenv runtime exports
# CARGO_NET_OFFLINE=true) — so do NOT hard-code `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

# OSS-Fuzz Rust libFuzzer+ASan flags. --cfg fuzzing matches libfuzzer-sys;
# force-frame-pointers aids ASan backtraces. $SANITIZER_FLAGS (clang flags from the
# base ENV) is the sanitizer TOGGLE for rustc: non-empty (default) => ASan via
# -Zsanitizer=address; explicitly empty (--build-arg SANITIZER_FLAGS=) => none.
# $RUST_DEBUG_FLAGS threads the debug-info contract (DWARF < 4, §6.2 item 10).
RUST_SAN=""
[ -n "${SANITIZER_FLAGS-x}" ] && RUST_SAN="-Zsanitizer=address"
RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:--Cdebuginfo=1 -Zdwarf-version=3}"
# libfuzzer-sys compiles libFuzzer's C++ runtime via the cc crate — keep its
# debug info at DWARF 3 too (clang-19's plain -g emits DWARF 5).
export CFLAGS="${CFLAGS:-} -gdwarf-3" CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"
FUZZ_RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing $RUST_SAN $RUST_DEBUG_FLAGS -Cforce-frame-pointers"

# The prebuilt ASan runtime shipped with rustc (librustc-*_rt.asan.a) carries
# DWARF 5 compile units, which would leak into the linked fuzz binary and break
# the DWARF < 4 contract. Strip its debug info (runtime frames are skipped in
# triage anyway); idempotent, so safe on the offline re-run.
find "$(rustc --print target-libdir)" -name 'librustc-*_rt.*.a' \
  -exec objcopy --strip-debug {} \; 2>/dev/null || true

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the project's OWN test suite with its NORMAL flags (clean, unsanitized) so
# mayhem/test.sh only RUNS it. The upstream fuzz/ crate is excluded: it depends on
# mozjs (SpiderMonkey, a git dep) which is not buildable in this image.
echo "=== cargo test --no-run (project's normal flags) ==="
RUSTFLAGS="" cargo test --no-run -p pulldown-cmark -p pulldown-cmark-escape

echo "build.sh complete"
