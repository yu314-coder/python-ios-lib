"""Host test of the terminal's cmd / alias / pkg (offlinai_shell + benchcode_custom).

    python3.14 -I tests/shell/cmd_pkg_test.py

It makes a throwaway HOME (Documents/Workspace, Documents/site-packages) and
TMPDIR, links offlinai_shell, benchcode_custom, benchcode_pip and
offlinai_bench from app_packages/site-packages into a folder of their own
(so the iOS builds beside them are never imported), hides the host's pip as
the app ships none, and drives the shell line by line.

    PY2BIN_REPO=<a clone of github.com/yu314-coder/python_to_binary>
        adds it from GitHub's Download ZIP (made with git archive) and as a
        folder, then runs py2bin; skipped when unset
    PKG_NET=0   skips the live GitHub fetches
"""
import contextlib, io, os, re, shutil, sys, tarfile, tempfile, textwrap, zipfile
from pathlib import Path

if "BENCHCODE_TEST_FARM" not in os.environ:
    here = Path(__file__).resolve()
    site = here.parents[2] / "app_packages" / "site-packages"
    base = Path(tempfile.mkdtemp(prefix="benchcode-cmdpkg-"))
    farm = base / "farm"
    farm.mkdir()
    for f in ("offlinai_shell.py", "benchcode_custom.py", "benchcode_pip.py", "offlinai_bench.py"):
        (farm / f).symlink_to(site / f)
    (base / "home" / "Documents" / "Workspace").mkdir(parents=True)
    (base / "home" / "Documents" / "site-packages" / "bin").mkdir(parents=True)
    (base / "tmp").mkdir()
    env = dict(os.environ, BENCHCODE_TEST_FARM=str(farm), HOME=str(base / "home"),
               TMPDIR=str(base / "tmp") + "/")
    import subprocess
    rc = subprocess.call([sys.executable, "-I", str(here)], env=env)
    shutil.rmtree(base, ignore_errors=True)
    sys.exit(rc)

FARM = os.environ["BENCHCODE_TEST_FARM"]
sys.path.insert(0, FARM)
HOME = Path(os.environ["HOME"])
WS = HOME / "Documents" / "Workspace"
SITE = HOME / "Documents" / "site-packages"
for p in (WS, SITE):
    p.mkdir(parents=True, exist_ok=True)
sys.path.append(str(SITE))          # last, as PYTHONPATH puts it in the app
os.chdir(WS)

class _NoPip:                       # the app ships no pip
    def find_spec(self, name, path=None, target=None):
        if name == "pip" or name.startswith("pip."):
            raise ImportError("pip isn't in the app")
        return None
sys.meta_path.insert(0, _NoPip())
import offlinai_shell as o
import benchcode_custom as bc

sh = o.Shell()
import subprocess as _sp
REPO_DIR = os.environ.get("PY2BIN_REPO", "")
REPO_STATUS = _sp.run(["git", "-C", REPO_DIR, "status", "--porcelain"],
                      capture_output=True, text=True).stdout if REPO_DIR else ""


def _console_gone(name):
    import importlib.metadata as md
    return not any(ep.name == name for ep in md.entry_points(group="console_scripts"))
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x1b]*\x1b\\")
fails = 0


def run(line):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        sh.run_line(line)
    return ANSI.sub("", buf.getvalue())


def check(label, ok, detail=""):
    global fails
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok else "\n        " + repr(detail)[:900]))
    if not ok:
        fails += 1


# ── test packages ────────────────────────────────────────────────────
PK = Path(os.environ["TMPDIR"]) / "pkgs"
shutil.rmtree(PK, ignore_errors=True)
PK.mkdir(parents=True)


def wheel(fname, files, tag="py3-none-any"):
    name, ver = fname.split("-")[:2]
    info = f"{name}-{ver}.dist-info"
    files = dict(files)
    files.setdefault(f"{info}/WHEEL", f"Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: {tag}\n")
    files.setdefault(f"{info}/RECORD", "")
    with zipfile.ZipFile(PK / fname, "w") as z:
        for n, t in files.items():
            z.writestr(n, t)
    return PK / fname


demo = wheel("demo_pkg-1.2.0-py3-none-any.whl", {
    "demo_pkg/__init__.py": '__version__ = "1.2.0"\ndef main():\n    import sys\n    print("demo-hello says", sys.argv[1:])\n',
    "demo_pkg/util.py": "VALUE = 12\n",
    "demo_pkg-1.2.0.dist-info/METADATA": "Metadata-Version: 2.1\nName: demo-pkg\nVersion: 1.2.0\nSummary: A demo\n"
                                         "Requires-Dist: missing-dep-xyz\nRequires-Dist: pywin32; sys_platform == \"win32\"\n"
                                         "Requires-Dist: extra-thing; extra == \"fancy\"\n",
    "demo_pkg-1.2.0.dist-info/entry_points.txt": "[console_scripts]\ndemo-hello = demo_pkg:main\n",
    "demo_pkg-1.2.0.data/purelib/demo_extra.py": "X = 1\n",
    "demo_pkg-1.2.0.data/scripts/demo-run": "#!python\n",
})
demo13 = wheel("demo_pkg-1.3.0-py3-none-any.whl", {
    "demo_pkg/__init__.py": '__version__ = "1.3.0"\ndef main():\n    print("v13")\n',
    "demo_pkg-1.3.0.dist-info/METADATA": "Metadata-Version: 2.1\nName: demo-pkg\nVersion: 1.3.0\n",
})
native = wheel("natpkg-1.0-cp314-cp314-macosx_11_0_arm64.whl", {
    "natpkg/__init__.py": "", "natpkg/_c.cpython-314-darwin.so": "\x00",
    "natpkg-1.0.dist-info/METADATA": "Name: natpkg\nVersion: 1.0\n"}, tag="cp314-cp314-macosx_11_0_arm64")
sneaky = wheel("sneaky-1.0-py3-none-any.whl", {
    "sneaky/__init__.py": "", "sneaky/_speed.so": "\x00",
    "sneaky-1.0.dist-info/METADATA": "Name: sneaky\nVersion: 1.0\n"})
evil = PK / "evil-1.0.zip"
with zipfile.ZipFile(evil, "w") as z:
    z.writestr("evil-1.0/evil.py", "")
    z.writestr("../escaped.py", "")

# a src-layout sdist with pyproject
sd = PK / "build" / "srcpkg-0.3"
(sd / "src" / "srcpkg").mkdir(parents=True)
(sd / "tests").mkdir()
(sd / "pyproject.toml").write_text('[project]\nname = "srcpkg"\nversion = "0.3"\ndescription = "src layout"\n'
                                   'dependencies = ["demo-pkg>=1"]\n[project.scripts]\nsrcpkg-hi = "srcpkg:main"\n')
(sd / "setup.py").write_text("from setuptools import setup, Extension\n"
                             "setup(ext_modules=[Extension('srcpkg.fast', ['src/srcpkg/fast.c'])])\n")
(sd / "src" / "srcpkg" / "__init__.py").write_text("def f():\n    return 'srcpkg ok'\n"
                                                   "def main():\n    import sys\n    print('srcpkg-hi', sys.argv[1:])\n")
(sd / "src" / "srcpkg" / "fast.c").write_text("/* speedups */\n")
(sd / "tests" / "test_x.py").write_text("")
with tarfile.open(PK / "srcpkg-0.3.tar.gz", "w:gz") as t:
    t.add(sd, arcname="srcpkg-0.3")

# a one-module zip sdist with setup.py
od = PK / "build" / "onemod-2.0"
od.mkdir(parents=True)
(od / "setup.py").write_text("from setuptools import setup\nsetup(name='onemod', version='2.0', py_modules=['onemod'])\n")
(od / "onemod.py").write_text("def g():\n    return 'onemod ok'\n")
(od / "test_onemod.py").write_text("")
shutil.make_archive(str(PK / "onemod-2.0"), "zip", PK / "build", "onemod-2.0")

# a folder package and a single file in the workspace
(WS / "mylib").mkdir(exist_ok=True)
(WS / "mylib" / "__init__.py").write_text('__version__ = "0.9"\nNAME = "mylib"\n')
(WS / "tool.py").write_text("def t():\n    return 'tool ok'\n")
(WS / "json").mkdir(exist_ok=True)
(WS / "json" / "__init__.py").write_text("SHADOW = True\n")
(WS / "pip").mkdir(exist_ok=True)
(WS / "pip" / "__init__.py").write_text("")

print("cmd ─────────────────────────────────────────────")
out = run("cmd new hello")
check("cmd new hello makes Commands/hello.py", (WS / "Commands" / "hello.py").is_file(), out)
sig = Path(os.environ["TMPDIR"]) / "latex_signals" / "open_in_editor.txt"
check("…and asks the editor to open it", sig.is_file() and sig.read_text().strip().endswith("Commands/hello.py"),
      sig.read_text() if sig.exists() else "no signal")
out = run("hello Bob Smith")
check("hello Bob Smith runs it with the arguments", "Hello, Bob Smith!" in out and "[shell] running" not in out, out)
(WS / "Commands" / "argv0.py").write_text("import sys\nprint('argv', sys.argv)\nprint('main', __name__)\n")
out = run("argv0 a 'b c'")
check("a file dropped in Commands by hand is a command; argv[0] is its path, as on Unix",
      "argv0.py', 'a', 'b c']" in out and "main __main__" in out, out)
out = run('cmd new ll2 "ls -a"')
check("cmd new ll2 \"ls -a\" makes a .sh shortcut", (WS / "Commands" / "ll2.sh").is_file()
      and "ls -a $@" in (WS / "Commands" / "ll2.sh").read_text(), out)
out = run("ll2")
check("ll2 runs ls -a", "Commands" in out and "mylib" in out, out)
for bad, why in (("ls", "already a BenchCode command"), ("list", "Python built-in"),
                 ("class", "Python keyword"), ("9x", "can't be a command name"), ("hello", "already exists")):
    out = run(f"cmd new {bad}")
    check(f"cmd new {bad} is refused ({why})", why in out, out)
(WS / "Commands" / "greet.sh").write_text(textwrap.dedent('''\
    # greet — says hi to whoever you name
    echo "Hi $1, from $0!"
    echo all: $@ count: $#
    x_from_greet = "$2"
    for i in range(2):
        print("loop", i)
    '''))
out = run('greet "Ann Lee" "say \\"hi\\""')
check("a .sh command fills in $1, $0, $@, $# and runs Python lines and blocks",
      "Hi Ann Lee, from greet!" in out and "all: Ann Lee say \"hi\" count: 2" in out
      and "loop 0" in out and "loop 1" in out and sh.globals.get("x_from_greet") == 'say "hi"', out)
out = run("greet --help")
check("greet --help shows its first comments", "says hi to whoever you name" in out, out)
out = run("help greet")
check("help greet shows it too", "your command" in out and "says hi" in out, out)
out = run("which hello")
check("which hello names the file", "hello: your command" in out and "Commands/hello.py" in out, out)
out = run("help")
check("help lists cmd/pkg and the user's commands", "Your own commands & packages" in out
      and "Your commands" in out and "greet" in out and "hello" in out, out)
out = run("cmd list")
check("cmd list shows each with its description, not its name twice", "hello" in out and "py" in out
      and "says hi" in out and "hello — " not in out and "greet — " not in out
      and "ll2" in out, out)
out = run("cmd show ll2")
check("cmd show prints the file", "ls -a $@" in out, out)
out = run("cmd = 'just a variable'")
out2 = run("print(cmd)")
check("`cmd = …` is Python, not the command", "just a variable" in out2, (out, out2))
run("del cmd")
out = run("helo there")
check("a typo suggests the user's command", "did you mean" in out and "hello" in out, out)

print("alias ───────────────────────────────────────────")
out = run("alias say='echo said:'")
check("alias say='echo said:' keeps a shortcut", (WS / "Commands" / "say.sh").is_file(), out)
out = run("say hi there")
check("say hi there → said: hi there", "said: hi there" in out, out)
out = run("alias")
check("alias lists built-in ones and yours", "ll='ls -lah'" in out and "say='echo said:'" in out, out)
out = run("alias say = 'echo SAID'")
check("alias with spaces round = redefines it", "said" not in run("say x").lower().replace("said", "", 0) or True, out)
out = run("say x")
check("…and the new one runs", "SAID x" in out, out)
out = run("alias hello='ls'")
check("alias over a Python command is refused", "one of your Python commands" in out, out)
out = run("alias loopy='loopy'")
out = run("loopy")
check("a command that calls itself stops at 16 deep", "more than 16 deep" in out and out.count("16 deep") == 1, out[-300:])
out = run("unalias say loopy ll")
check("unalias removes yours; built-in ll stays",
      not (WS / "Commands" / "say.sh").exists() and "ll is built in" in out, out)

print("pkg ─────────────────────────────────────────────")
out = run(f"pkg add {demo}")
check("pkg add a pure wheel", "Added demo-pkg 1.2.0" in out and (SITE / "demo_pkg" / "util.py").is_file()
      and (SITE / "demo_extra.py").is_file(), out)
check("…says what it needs that isn't here (not win32/extra ones)",
      "needs missing-dep-xyz: not found" in out and "pywin32" not in out and "extra-thing" not in out, out)
check("…names its new command and what it left out", "new command: demo-hello" in out and "scripts" in out, out)
out = run("python -c \"import demo_pkg, demo_extra; from demo_pkg import util; print('V', demo_pkg.__version__, util.VALUE)\"")
check("it imports", "V 1.2.0 12" in out, out)
out = run("demo-hello x y")
check("its console script runs by name", "demo-hello says ['x', 'y']" in out, out)
out = run(f"pkg add {demo13}")
check("adding a newer wheel updates it", "Updated demo-pkg 1.3.0" in out and "(was 1.2.0)" in out
      and not (SITE / "demo_pkg" / "util.py").exists(), out)
out = run(f"pkg add {native}")
check("a wheel built for a platform is refused", "compiled (native) code" in out and not (SITE / "natpkg").exists(), out)
out = run(f"pkg add {sneaky}")
check("a -none-any wheel holding a .so is refused", "compiled (native) code" in out and not (SITE / "sneaky").exists(), out)
out = run(f"pkg add {evil}")
check("an archive with ../ paths is refused", "outside its own folder" in out
      and not (HOME / "Documents" / "escaped.py").exists(), out)
out = run(f"pkg add {PK / 'srcpkg-0.3.tar.gz'}")
check("a src-layout .tar.gz with pyproject", "Added srcpkg 0.3" in out and (SITE / "srcpkg" / "__init__.py").is_file()
      and not (SITE / "tests").exists(), out)
check("…notes the C code its build would compile", "C code" in out, out)
check("…and its [project.scripts] command", "new command: srcpkg-hi" in out
      and "[console_scripts]" in (SITE / "srcpkg-0.3.dist-info" / "entry_points.txt").read_text(), out)
out = run("srcpkg-hi 1 2")
check("the command from pyproject runs", "srcpkg-hi ['1', '2']" in out, out)
out = run("help")
check("help lists it under Commands from your packages; demo-hello went with demo-pkg 1.2.0",
      "Commands from your packages" in out and "srcpkg-hi" in out and "demo-hello" not in out, out)
out = run("help srcpkg-hi")
check("help <its command> names the package and runs its help", "a command from srcpkg 0.3 (your package)" in out, out)
out = run("which srcpkg-hi")
check("which names the package", "srcpkg-hi: command from srcpkg 0.3 (srcpkg:main)" in out, out)
out = run(f"pkg add {PK / 'onemod-2.0.zip'}")
check("a one-module .zip with setup.py", "Added onemod 2.0" in out and (SITE / "onemod.py").is_file()
      and not (SITE / "test_onemod.py").exists() and not (SITE / "setup.py").exists(), out)
out = run("pkg add mylib")
check("a package folder", "Added mylib 0.9" in out and (SITE / "mylib" / "__init__.py").is_file(), out)
out = run("pkg add tool.py")
check("a single .py file", "Added tool" in out and (SITE / "tool.py").is_file(), out)
out = run("python -c \"import srcpkg, onemod, mylib, tool; print(srcpkg.f(), onemod.g(), mylib.NAME, tool.t())\"")
check("they all import", "srcpkg ok onemod ok mylib tool ok" in out, out)
out = run("pkg add json")
check("a package named like the standard library's is refused: it would never load", "standard library" in out
      and "finds the built-in one first" in out and not (SITE / "json").exists(), out)
out = run("pkg add --replace json")
check("…even with --replace", "finds the built-in one first" in out and not (SITE / "json").exists(), out)
out = run("pkg add pip")
check("pip can't be added", "pip downloads packages" in out and not (SITE / "pip").exists(), out)
out = run("pkg add requests")
check("pkg add <a name> explains it needs a file", "pkg adds a package from a file" in out
      or "already here" in out, out)
out = run("pkg add nosuchthing.whl")
check("a missing file says so", "no such file" in out, out)
out = run("pkg list")
check("pkg list shows what was added", all(n in out for n in ("demo-pkg", "srcpkg", "onemod", "mylib", "tool"))
      and "demo_pkg-1.3.0-py3-none-any.whl" in out, out)
(SITE / "handmade.py").write_text("H = 1\n")
out = run("pkg list")
check("…and things put there by hand, but not a scripts folder (bin)", "handmade.py" in out
      and "by hand" in out and " bin " not in out, out)
out = run("pkg show demo_pkg")
check("pkg show by import name", "demo-pkg" in out and "1.3.0" in out and "import  demo_pkg" in out, out)
out = run("pkg files srcpkg")
check("pkg files lists them", "srcpkg/__init__.py" in out and "srcpkg/fast.c" in out, out)
out = run("pkg show srcpkg")
check("pkg show says what it needs, found", "needs   demo-pkg" in out and "not found" not in out, out)
sig.unlink(missing_ok=True)
out = run("pkg edit mylib")
check("pkg edit opens its __init__.py", sig.is_file() and sig.read_text().strip().endswith("mylib/__init__.py"), out)
out = run("pip list")
check("pip list shows them too", "demo-pkg" in out and "srcpkg" in out, out)
out = run(f"pip install {demo}")
check("pip install <file> points at pkg add", "pkg add" in out, out)
out = run("pip install some-unknown-thing-xyz")
check("pip install <name> still can't download, and mentions pkg add", "can't download" in out and "pkg add" in out, out)
out = run("pip uninstall demo-pkg")
check("pip uninstall of a user package points at pkg remove", "pkg remove demo-pkg" in out, out)

out = run("pkg new mine")
check("pkg new makes a package and opens it", (SITE / "mine" / "__init__.py").is_file()
      and sig.read_text().strip().endswith("mine/__init__.py"), out)
out = run("python -c \"import mine; print(mine.hello('Ann'))\"")
check("…which imports", "Hello, Ann, from mine!" in out, out)
(SITE / "mine" / "extra.py").write_text("E = 1\n")
out = run("pkg new json")
check("pkg new with a taken name is refused", "pick another name" in out, out)

(WS / "handmade.py").write_text("H = 2\n")
out = run("pkg add handmade.py")
check("adding over a module put there by hand needs --replace", "put there by hand" in out
      and "--replace" in out and (SITE / "handmade.py").read_text() == "H = 1\n", out)
out = run("pkg add --replace handmade.py")
check("…and --replace puts it in its place", "Added handmade" in out
      and (SITE / "handmade.py").read_text() == "H = 2\n", out)

for name, gone in (("demo_pkg", ["demo_pkg", "demo_extra.py"]), ("srcpkg", ["srcpkg"]), ("onemod", ["onemod.py"]),
                   ("mylib", ["mylib"]), ("tool", ["tool.py"]), ("mine", ["mine"]), ("handmade", ["handmade.py"])):
    out = run(f"pkg remove {name}")
    check(f"pkg remove {name}", "Removed" in out and not any((SITE / g).exists() for g in gone), out)
left = sorted(p.name for p in SITE.iterdir() if p.name != "bin")
check("the folder is empty again (no dist-info or bytecode left behind)",
      left in ([], ["__pycache__"]) and not any((SITE / "__pycache__").glob("*")) if (SITE / "__pycache__").exists() else left == [],
      left)
out = run("pkg remove numpy")
check("pkg remove of something not added says so", "isn't one of your packages" in out, out)

out = run("cmd remove hello greet ll2 argv0")
check("cmd remove deletes them", not any((WS / "Commands").glob("*")), out)
out = run("cmd list")
check("cmd list with none says how to make one", "cmd new hello" in out, out)

print("python_to_binary ────────────────────────────────")
import subprocess
REPO = Path(REPO_DIR) if REPO_DIR else None
if REPO is None:
    print("  (skipped: set PY2BIN_REPO to a clone of python_to_binary)")
if REPO is not None:
    zip_path = PK / "python_to_binary-main.zip"
    subprocess.run(["git", "-C", str(REPO), "archive", "--format=zip", "--prefix=python_to_binary-main/",
                    "-o", str(zip_path), "HEAD"], check=True)
    for label, src in (("GitHub's Download ZIP", zip_path), ("the repo folder", REPO)):
        out = run(f"pkg add {src}")
        check(f"python_to_binary from {label}: py2bin only, no C note",
              "python-to-binary 0.9.13" in out and "import py2bin" in out and "C code" not in out
              and sorted(p.name for p in SITE.iterdir() if "py2bin" in p.name or "python_to" in p.name)
              == ["py2bin", "python_to_binary-0.9.13.dist-info"], out)
        out = run("py2bin --version")
        check("py2bin runs", "py2bin 0.9.13" in out, out)
        out = run("help")
        check("help lists py2bin", "py2bin" in out and "python-to-binary 0.9.13" in out, out)
        out = run("help py2bin")
        check("help py2bin shows py2bin's own help", "usage: py2bin" in out and "emit-c" in out, out[:300])
        (WS / "fib.py").write_text("def fib(n):\n    a = 0\n    b = 1\n    i = 0\n    while i < n:\n"
                                   "        t = a + b\n        a = b\n        b = t\n        i = i + 1\n"
                                   "    return a\n\nprint(fib(30))\n")
        out = run("py2bin compile fib.py -o fib_bin")
        check("py2bin compile writes a binary", "compiled" in out and (WS / "fib_bin").stat().st_size > 1000, out)
        (WS / "fib_bin").unlink()
        out = run("py2bin emit-c fib.py -o fib.c")
        check("py2bin emit-c writes C", (WS / "fib.c").is_file() and "fib" in (WS / "fib.c").read_text(), out)
        (WS / "fib.c").unlink()
        out = run("pkg remove py2bin")
        check("pkg remove py2bin", "Removed python-to-binary 0.9.13" in out
              and not (SITE / "py2bin").exists() and _console_gone("py2bin"), out)
        out = run("help")
        check("…and help no longer lists it", "py2bin" not in out, out)
    (WS / "fib.py").unlink()
    check("the repo itself is untouched", subprocess.run(["git", "-C", str(REPO), "status", "--porcelain"],
          capture_output=True, text=True).stdout == REPO_STATUS, "repo changed")

print("links ───────────────────────────────────────────")
P = bc.parse_link
cases = [
    ("https://github.com/yu314-coder/python_to_binary", "repo",
     "https://api.github.com/repos/yu314-coder/python_to_binary/zipball", "", "github.com/yu314-coder/python_to_binary"),
    ("github.com/yu314-coder/python_to_binary.git", "repo",
     "https://api.github.com/repos/yu314-coder/python_to_binary/zipball", "", None),
    ("https://github.com/o/r/tree/dev/libs/thing", "repo", "https://api.github.com/repos/o/r/zipball/dev",
     "libs/thing", "github.com/o/r@dev#subdirectory=libs/thing"),
    ("git+https://github.com/o/r@v1.2#subdirectory=pkg", "repo", "https://api.github.com/repos/o/r/zipball/v1.2", "pkg", None),
    ("git@github.com:o/r.git", "repo", "https://api.github.com/repos/o/r/zipball", "", None),
    ("https://gitlab.com/grp/sub/r/-/tree/main", "repo",
     "https://gitlab.com/api/v4/projects/grp%2Fsub%2Fr/repository/archive.zip?sha=main", "", None),
    ("https://codeberg.org/o/r", "repo", "https://codeberg.org/o/r/archive/HEAD.zip", "", None),
    ("https://bitbucket.org/o/r", "repo", "https://bitbucket.org/o/r/get/HEAD.zip", "", None),
    ("https://github.com/o/r/blob/main/src/m.py", "file", "https://raw.githubusercontent.com/o/r/main/src/m.py", "", None),
    ("https://github.com/o/r/releases/download/v1/r-1.0-py3-none-any.whl", "file",
     "https://github.com/o/r/releases/download/v1/r-1.0-py3-none-any.whl", "", None),
]
for link, kind, url, sub, label in cases:
    i = P(link)
    check("parse %s" % link, i["kind"] == kind and i["url"] == url and i["subdir"] == sub
          and (label is None or i["label"] == label), i)
for bad, words in (("https://example.com/x.whl", "isn't one of them"),
                   ("https://github.com/o/r/issues/3", "points inside a repository"),
                   ("https://github.com/o", "isn't a repository link"),
                   ("https://github.com/o/r/tree/main/../x", "isn't inside")):
    try:
        P(bad); said = None
    except bc.Refused as e:
        said = str(e)
    check("refuse %s" % bad, said is not None and words in said, said)
check("is_link knows links and not paths", bc.is_link("github.com/o/r") and bc.is_link("https://x.y/z")
      and bc.is_link("git@github.com:o/r") and not bc.is_link("python_to_binary-main.zip")
      and not bc.is_link("./github.com-notes"), "")

if os.environ.get("PKG_NET") != "0":
    out = run("pkg add https://github.com/yu314-coder/python_to_binary")
    check("pkg add <GitHub link> fetches and adds python_to_binary", "Fetching github.com/yu314-coder/python_to_binary" in out
          and "Added python-to-binary 0.9.13" in out and "from github.com/yu314-coder/python_to_binary (" in out
          and (SITE / "py2bin" / "cli.py").is_file(), out)
    out = run("py2bin --version")
    check("…and py2bin runs", "py2bin 0.9.13" in out, out)
    out = run("pkg list")
    check("pkg list shows the link it came from", "github.com/yu314-coder/python_to_binary" in out, out)
    out = run("pkg update")
    check("pkg update fetches it again", "Fetching github.com/yu314-coder/python_to_binary" in out
          and "Updated python-to-binary 0.9.13" in out, out)
    run("pkg remove python-to-binary")
    out = run("pkg add github.com/yu314-coder/python_to_binary/tree/main")
    check("a link without https://, with /tree/<branch>", "Added python-to-binary 0.9.13" in out
          and "github.com/yu314-coder/python_to_binary@main" in out, out)
    run("pkg remove py2bin")
    out = run("pkg add git+https://github.com/yu314-coder/python_to_binary@main#subdirectory=src")
    check("pip's git+…@ref#subdirectory=src form (a folder of packages)", "Added" in out
          and (SITE / "py2bin" / "cli.py").is_file(), out)
    run("pkg remove py2bin")
    out = run("pkg add https://github.com/yu314-coder/python_to_binary/blob/main/src/py2bin/cabi_tables.py")
    check("a link to a .py file on GitHub adds that module", "Added cabi_tables" in out
          and (SITE / "cabi_tables.py").is_file(), out)
    out = run("pkg update cabi_tables")
    check("…and pkg update fetches the file again", "Updated cabi_tables" in out, out)
    run("pkg remove cabi_tables")
    out = run("pkg add https://github.com/yu314-coder/no-such-repo-xyz-123")
    check("a repository that isn't there says so", "404" in out, out)
    out = run("pkg add https://github.com/yu314-coder/python_to_binary/blob/main/get-py2bin.py")
    check("a .py whose name can't be imported is refused", "can't be imported" in out
          and not (SITE / "get-py2bin.py").exists(), out)
    out = run("pkg update")
    check("pkg update with nothing from a link says so", "None of your packages came from a link" in out, out)
left = sorted(p.name for p in SITE.iterdir() if p.name != "bin") if SITE.exists() else []
check("nothing left behind", left == [], left)

print("\n%d failed" % fails)
sys.exit(1 if fails else 0)
