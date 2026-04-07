#!/usr/bin/env python3
"""iOS Fortran compiler wrapper: uses flang for compilation, clang for linking."""
import sys
import os
import subprocess

IOS_SDK = subprocess.check_output(
    ['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True
).strip()

FLANG = '/opt/homebrew/bin/flang-new'
TARGET = 'arm64-apple-ios17.0'

# Find flang runtime library directory once
FLANG_RT_DIR = ''
try:
    # flang-new uses -print-file-name (single dash)
    rt = subprocess.check_output(
        [FLANG, '-print-file-name=libFortranRuntime.a'], text=True, stderr=subprocess.DEVNULL
    ).strip()
    if os.path.exists(rt):
        FLANG_RT_DIR = os.path.dirname(rt)
except Exception:
    pass
if not FLANG_RT_DIR:
    # Try common homebrew paths
    for p in ['/opt/homebrew/lib', '/opt/homebrew/Cellar/flang/22.1.2/lib']:
        if os.path.isfile(os.path.join(p, 'libFortranRuntime.a')):
            FLANG_RT_DIR = p
            break

SKIP_STARTSWITH = ('-F', '-idirafter', '-Wno-', '-fvisibility', '-fdiagnostics-color', '-Minform')
SKIP_EXACT = {'-MD', '-MP', '-fvisibility=hidden', '-fdiagnostics-color=always'}
SKIP_WITH_NEXT = {'-MF', '-MQ', '-framework'}
# Old classic-flang runtime libs that don't exist in LLVM flang
SKIP_LIBS = {'-lflang', '-lpgmath', '-lflangrti', '-lompstub'}

def filter_args(args, for_linking=False):
    result = []
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
            continue
        if arg in SKIP_WITH_NEXT:
            skip_next = True
            continue
        if arg in SKIP_EXACT:
            continue
        if arg in SKIP_LIBS:
            continue
        if any(arg.startswith(p) for p in SKIP_STARTSWITH):
            continue
        if arg.startswith('-F') and len(arg) > 2 and arg[2] == '/':
            if for_linking:
                result.append(arg)  # keep -F for clang linker
            continue
        # Convert gfortran's -module to flang's -module-dir
        if arg == '-module' and not for_linking:
            result.append('-module-dir')
            continue
        result.append(arg)
    return result

args = sys.argv[1:]
is_compile = '-c' in args

if is_compile:
    filtered = filter_args(args, for_linking=False)
    cmd = [FLANG, '-target', TARGET, '-isysroot', IOS_SDK] + filtered
else:
    filtered = filter_args(args, for_linking=True)
    final = []
    for a in filtered:
        if a == '-bundle':
            final.append('-Wl,-bundle')
        else:
            final.append(a)
    # Add flang runtime libs
    if FLANG_RT_DIR:
        final.extend(['-L' + FLANG_RT_DIR, '-lFortranRuntime', '-lFortranDecimal'])
    cmd = ['clang', '-target', TARGET, '-isysroot', IOS_SDK] + final

ret = subprocess.call(cmd)
sys.exit(ret)
