#!/usr/bin/env bash
# Build + run the C / C++ / Fortran interpreter test harness on the host.
# Usage: ./interpreter_tests/run.sh
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CC="${CC:-clang}"
OUT="${TMPDIR:-/tmp}/test_interpreters"

echo "[build] compiling interpreters + harness with $CC ..."
"$CC" -O0 -g \
    -Igcc -Icpp -Ifortran \
    interpreter_tests/test_interpreters.c \
    gcc/offlinai_cc.c \
    cpp/offlinai_cpp.c \
    fortran/offlinai_fortran.c \
    -o "$OUT"

echo "[run] $OUT"
echo
"$OUT"
