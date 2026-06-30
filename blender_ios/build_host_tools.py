#!/usr/bin/env python3
"""Build host-native Blender code generators (makesdna, makesrna, ...) by reusing
the cross-build's exact compile commands with the iOS target triple stripped.

Blender has no cross-compile support: it builds these generators with the iOS
toolchain then runs them in-place to emit dna.cc/rna_*.cc. We instead compile the
same sources for the macOS host, link minimally (the generators only need their
own objects; the OIIO/framework link deps are spurious), and later patch Blender
to IMPORT these host binaries when CMAKE_CROSSCOMPILING.

Usage: build_host_tools.py <ninja-target> <out-binary-name>
  e.g. build_host_tools.py bin/makesdna.app/makesdna makesdna
"""
import os, subprocess, sys, shlex

BUILD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "blender")
HOSTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "host-tools")
OBJDIR = os.path.join(HOSTDIR, "obj")

# iOS-only flags to strip (each is either standalone or "flag <value>").
STRIP_WITH_VALUE = {"-isysroot", "-arch"}
STRIP_EXACT = {"-mdynamic-no-pic"}
STRIP_PREFIX = ("-miphoneos-version-min=",)

def transform_compile(cmd):
    """Return (host_cmd_list, output_obj_path) for a compile command, or None."""
    # Strip a leading shell wrapper like "cd X && " or ": && ... && :".
    if "&&" in cmd:
        cmd = cmd.split("&&", 1)[1] if cmd.strip().startswith((":", "cd")) else cmd
    toks = shlex.split(cmd)
    if "-c" not in toks:
        return None  # not a compile command
    out = []
    i = 0
    obj = None
    while i < len(toks):
        t = toks[i]
        if t in STRIP_WITH_VALUE:
            i += 2
            continue
        if t in STRIP_EXACT or t.startswith(STRIP_PREFIX):
            i += 1
            continue
        if t == "-o":
            # redirect object into the host obj dir, mirroring the relative path
            orig = toks[i + 1]
            obj = os.path.join(OBJDIR, orig.replace("/", "__"))
            out += ["-o", obj]
            i += 2
            continue
        out.append(t)
        i += 1
    return out, obj

def main():
    target, outname = sys.argv[1], sys.argv[2]
    os.makedirs(OBJDIR, exist_ok=True)
    # When building tool X, its transitive build pulls in OTHER generators'
    # executable objects (e.g. makesrna depends on running makesdna), whose own
    # main()/private symbols collide. Exclude foreign tool executable dirs; the
    # shared libs makesrna actually needs (bf_dna*, blenlib) live in their own
    # .dir and are kept. Object paths have '/' replaced by '__'.
    TOOLS = ["makesdna", "makesrna", "datatoc", "shader_tool"]
    foreign = [f"CMakeFiles__{t}.dir__" for t in TOOLS if t != outname]
    cmds = subprocess.run(["ninja", "-C", BUILD, "-t", "commands", target],
                          capture_output=True, text=True).stdout.splitlines()
    objs = []
    n_compiled = 0
    seen_src = {}  # source path -> obj, so a source shared across targets is built once
    for cmd in cmds:
        if " -c " not in f" {cmd} ":
            continue
        res = transform_compile(cmd)
        if not res:
            continue
        host_cmd, obj = res
        if obj is None:
            print(f"SKIP (no -o): {cmd[:120]}")
            continue
        if any(m in obj for m in foreign):
            continue  # foreign generator's executable object — skip
        # Dedup: the same .cc can appear under several target object dirs (e.g.
        # the blenlib subset in both makesdna and bf_dna_blenlib) -> duplicate
        # symbols at link. Compile each unique source exactly once.
        this_src = next((t for t in host_cmd if t.endswith((".cc", ".c", ".cpp"))), None)
        if this_src in seen_src:
            continue  # already compiled this source under another target dir
        # Force the host compiler (not the iOS one) — use clang++/clang from PATH.
        if host_cmd[0].endswith("++") or "c++" in host_cmd[0]:
            host_cmd[0] = "/usr/bin/clang++"
        else:
            host_cmd[0] = "/usr/bin/clang"
        src = next((t for t in reversed(host_cmd) if t.endswith((".cc", ".c", ".cpp"))), "?")
        r = subprocess.run(host_cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"COMPILE FAILED: {os.path.basename(src)}")
            print(r.stderr[-3500:])
            sys.exit(1)
        objs.append(obj)
        if this_src is not None:
            seen_src[this_src] = obj
        n_compiled += 1
    print(f"compiled {n_compiled} host objects")
    # Minimal host link: just the objects + libc++ (generators need nothing else).
    out_bin = os.path.join(HOSTDIR, outname)
    # Extra host link libs (e.g. host libfmt.a for makesrna) via env var.
    extra = os.environ.get("HOST_EXTRA_LIBS", "").split()
    link = ["/usr/bin/clang++", "-o", out_bin] + objs + extra + ["-lc++"]
    r = subprocess.run(link, capture_output=True, text=True)
    if r.returncode != 0:
        print("LINK FAILED:")
        print(r.stderr[-4000:])
        sys.exit(2)
    print(f"LINKED host binary: {out_bin}")
    # Sanity: run it with no args (most generators print usage / exit non-fatally).
    print(f"arch: ", end="", flush=True)
    subprocess.run(["lipo", "-archs", out_bin])

if __name__ == "__main__":
    main()
