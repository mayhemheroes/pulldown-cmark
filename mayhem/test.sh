#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the project's OWN test suite (pre-built by mayhem/build.sh via
# `cargo test --no-run`): the full unit + integration + doc test suite of the
# pulldown-cmark and pulldown-cmark-escape workspace crates (incl. the CommonMark
# spec suite and regression suites under pulldown-cmark/tests/). Behavioral: every
# test asserts parser events / rendered HTML against expected values.
# Emits a CTRF summary and exits non-zero iff any test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

LOG=/tmp/cargo-test.log
rc=0
RUSTFLAGS="" cargo test -p pulldown-cmark -p pulldown-cmark-escape 2>&1 | tee "$LOG" || rc=$?

# Sum the per-binary "test result: ok. P passed; F failed; I ignored; ..." lines.
read -r P F S N <<<"$(awk '
  /^test result: / {
    for (i = 1; i <= NF; i++) {
      if ($(i+1) ~ /^passed/)  p += $i
      if ($(i+1) ~ /^failed/)  f += $i
      if ($(i+1) ~ /^ignored/) s += $i
    }
    n++
  }
  END { printf "%d %d %d %d", p, f, s, n }' "$LOG")"

if [ "$N" -eq 0 ]; then
  echo "ERROR: no 'test result:' lines found — the pre-built test suite did not run" >&2
  emit_ctrf "cargo-test" 0 1 0
  exit 1
fi

# Perturbation guard: cargo exiting non-zero counts as a failure even if the
# summary lines parsed clean (e.g. a test binary that died mid-run).
if [ "$rc" -ne 0 ] && [ "$F" -eq 0 ]; then F=1; fi

emit_ctrf "cargo-test" "$P" "$F" "$S"
