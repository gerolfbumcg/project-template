#!/usr/bin/env python3
"""
check_env_paths.py -- static check for absolute paths and environment usage.

Inspects Python and R source code for:

  ABS001  absolute path literal (/..., ~/..., C:\\..., \\\\server\\...)
  ABS002  working directory set explicitly (setwd / os.chdir)
  ENV001  environment variable used but not listed in .env.example
  ENV002  key in .env.example that is never used (only with --check-unused)
  ENV003  environment variable read with a non-constant name (cannot be checked)
  SEC001  credential-like name assigned a literal string value
  SEC002  connection string with embedded credentials
  SEC003  .env.example holds what looks like a real value instead of a placeholder
  FILE001 file that should never be in the repository (.env, .Renviron, ...)

Deliberately dependency-free: standard library only, so the hook runs without a
virtualenv and without an R installation.

Exit codes: 0 = clean, 1 = findings, 2 = usage error.

To silence a single line, append `# envcheck: ignore` to it (works in both
Python and R, since both use #).
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    tomllib = None


# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

DEFAULT_CONFIG: dict = {
    "env_example": ".env.example",
    # Variables that are always acceptable, even if absent from .env.example.
    "env_vars_optional": [
        "HOME", "USER", "USERNAME", "PATH", "TMPDIR", "TEMP", "LANG",
        "R_HOME", "R_LIBS_USER", "RETICULATE_PYTHON", "CI", "PYTEST_CURRENT_TEST",
    ],
    # Path prefixes that may legitimately be absolute (regex, matched on the literal).
    "allow_path_regex": [
        r"^/$",
        r"^/dev/null$",
        r"^/api/",          # URL paths, not filesystem paths
        r"^/v\d+/",
    ],
    # Directories that are never scanned.
    "ignore_dirs": [
        ".git", ".venv", "venv", "env", "__pycache__", ".pytest_cache", ".mypy_cache",
        "node_modules", "renv", "packrat", ".Rproj.user", "_freeze", ".quarto",
        "site-packages", ".ipynb_checkpoints", "build", "dist",
    ],
    # Paths (relative to the project root) for which ABS/SEC checks are skipped.
    "ignore_paths": [],
    "extensions": [".py", ".ipynb", ".R", ".r", ".Rmd", ".rmd", ".qmd"],
    # Project-defined wrapper functions that read an environment variable and
    # take the variable name as their first argument, e.g. required("DB_HOST").
    "env_getters": [],
    # Files that simply should not exist in the repository.
    "forbidden_files": [
        ".env", ".env.local", ".Renviron", ".RData", ".Rhistory",
        "credentials.json", "secrets.yaml", "secrets.yml", "id_rsa", "id_ed25519",
    ],
    "fail_on_unused": True,
}


@dataclass
class Config:
    root: Path
    data: dict = field(default_factory=lambda: dict(DEFAULT_CONFIG))

    def __getitem__(self, key):
        return self.data[key]

    @property
    def allow_path_re(self):
        return [re.compile(p) for p in self.data["allow_path_regex"]]


def load_config(root: Path, explicit: Path | None) -> Config:
    """Reads [tool.envcheck] from .envcheck.toml or pyproject.toml."""
    cfg = dict(DEFAULT_CONFIG)
    candidates = [explicit] if explicit else [root / ".envcheck.toml", root / "pyproject.toml"]
    for path in candidates:
        if path is None or not path.is_file():
            continue
        if tomllib is None:
            print(f"envcheck: tomllib unavailable (Python < 3.11), ignoring {path.name}",
                  file=sys.stderr)
            break
        with path.open("rb") as fh:
            doc = tomllib.load(fh)
        section = doc.get("tool", {}).get("envcheck", doc.get("envcheck", {}))
        if section:
            cfg.update(section)
        break
    return Config(root=root, data=cfg)


# --------------------------------------------------------------------------
# Findings
# --------------------------------------------------------------------------

@dataclass
class Finding:
    path: str
    line: int
    col: int
    code: str
    message: str

    def render(self) -> str:
        return f"{self.path}:{self.line}:{self.col}: {self.code} {self.message}"


# --------------------------------------------------------------------------
# Detection patterns
# --------------------------------------------------------------------------

ABS_PATH_RE = re.compile(
    r"""^(
          /[^\s/*?][^\n]*          # POSIX: /mnt/share/data
        | ~(/[^\n]*)?              # home: ~ of ~/data
        | [A-Za-z]:[\\/][^\n]*     # Windows: C:\data
        | \\\\[^\\\s]+\\[^\n]*     # UNC: \\server\share
    )$""",
    re.VERBOSE,
)

SECRET_NAME_RE = re.compile(
    r"(?i)(^|_)(pass(word|wd)?|secret|token|api_?key|apikey|access_?key|"
    r"private_?key|credential|auth|pat|dsn)($|_)"
)

CONN_STRING_RE = re.compile(
    r"(?i)(postgres(ql)?|mysql|mariadb|mongodb|mssql|redis|amqp|sftp|ftp)://"
    r"[^/\s:@]+:[^/\s@]+@"          # user:pass@
)

ODBC_RE = re.compile(r"(?i)\b(pwd|password|uid)\s*=\s*[^;\s]+", re.IGNORECASE)

# Placeholder values that are not real secrets.
PLACEHOLDER_RE = re.compile(
    r"^(|x+|\.{3}|<[^>]*>|\{\{?[^}]*\}?\}|\$\{?[A-Z_][A-Z0-9_]*\}?|"
    r"(?i:changeme|dummy|placeholder|example|todo|fixme|test|fake|redacted|none|null))$"
)

# Looser pattern, only for key names in .env.example (there 'KEY' is suspicious).
SECRET_ENVNAME_RE = re.compile(
    r"(?i)(^|_)(pass(word|wd)?|secret|token|key|credential|auth|pat|dsn|salt)($|_)"
)

SUPPRESS_RE = re.compile(r"#\s*envcheck:\s*ignore\b")


def is_allowed_path(value: str, cfg: Config) -> bool:
    return any(rx.search(value) for rx in cfg.allow_path_re)


def looks_like_path(value: str) -> bool:
    """Filters out regex patterns and format strings that happen to start with /."""
    if len(value) < 2:
        return False
    if any(ch in value for ch in "\n\t"):
        return False
    # Regex-like: contains groups, character classes or anchors.
    if re.search(r"[\[\]()|^$+]", value) and not re.search(r"[\w.-]/[\w.-]", value):
        return False
    return True


# --------------------------------------------------------------------------
# Python analysis (via ast)
# --------------------------------------------------------------------------

ENV_GETTERS = {"getenv", "get"}


def _attr_chain(node: ast.AST) -> str:
    """os.environ.get -> 'os.environ.get'"""
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def check_python(source: str, relpath: str, lines: list[str], cfg: Config,
                 line_offset: int = 0) -> tuple[list[Finding], dict[str, tuple]]:
    findings: list[Finding] = []
    used: dict[str, tuple] = {}

    def note(key: str, node: ast.AST) -> None:
        used.setdefault(key, (relpath,
                              getattr(node, "lineno", 1) + line_offset,
                              getattr(node, "col_offset", 0) + 1))

    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        findings.append(Finding(relpath, (exc.lineno or 1) + line_offset, exc.offset or 1,
                                "PARSE01", f"could not parse file: {exc.msg}"))
        return findings, used

    # Constants inside an f-string must not be reported twice.
    in_fstring = {id(v) for n in ast.walk(tree) if isinstance(n, ast.JoinedStr)
                  for v in ast.walk(n) if isinstance(v, ast.Constant)}

    def add(node: ast.AST, code: str, msg: str) -> None:
        line = getattr(node, "lineno", 1) + line_offset
        col = getattr(node, "col_offset", 0) + 1
        if 0 < line <= len(lines) and SUPPRESS_RE.search(lines[line - 1]):
            return
        findings.append(Finding(relpath, line, col, code, msg))

    for node in ast.walk(tree):
        # --- string literals: absolute paths and connection strings ----------
        if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and id(node) not in in_fstring:
            val = node.value
            if CONN_STRING_RE.search(val):
                add(node, "SEC002", "connection string with embedded credentials")
            elif ODBC_RE.search(val) and "=" in val and ";" in val:
                add(node, "SEC002", "ODBC-style connection string containing a password")
            elif ABS_PATH_RE.match(val) and looks_like_path(val) and not is_allowed_path(val, cfg):
                add(node, "ABS001", f"absolute path in code: {val!r}")

        # --- f-strings: the leading text decides whether the path is absolute -
        if isinstance(node, ast.JoinedStr):
            first = node.values[0] if node.values else None
            if isinstance(first, ast.Constant) and isinstance(first.value, str):
                val = first.value
                if ABS_PATH_RE.match(val) and looks_like_path(val + "x") \
                        and not is_allowed_path(val, cfg):
                    add(node, "ABS001", f"f-string starts with an absolute path: {val!r}")

        # --- os.chdir --------------------------------------------------------
        if isinstance(node, ast.Call) and _attr_chain(node.func) in ("os.chdir", "chdir"):
            add(node, "ABS002", "os.chdir() hard-codes the working directory")

        # --- os.getenv / os.environ.get --------------------------------------
        if isinstance(node, ast.Call):
            chain = _attr_chain(node.func)
            tail = chain.rsplit(".", 1)[-1]
            custom = set(cfg["env_getters"])
            is_env_call = chain in ("os.getenv", "os.environ.get", "environ.get", "getenv") or (
                tail in ENV_GETTERS and chain.endswith("environ.get")
            ) or chain in custom or tail in custom
            if is_env_call and node.args:
                arg = node.args[0]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    note(arg.value, arg)
                else:
                    add(node, "ENV003", "environment variable with a non-constant name")

        # --- os.environ["X"] --------------------------------------------------
        if isinstance(node, ast.Subscript):
            if _attr_chain(node.value) in ("os.environ", "environ"):
                key = node.slice
                if isinstance(key, ast.Constant) and isinstance(key.value, str):
                    note(key.value, key)
                else:
                    add(node, "ENV003", "environment variable with a non-constant name")

        # --- credential-like assignments --------------------------------------
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            names = [t.id for t in targets if isinstance(t, ast.Name)]
            names += [t.attr for t in targets if isinstance(t, ast.Attribute)]
            value = node.value
            if names and isinstance(value, ast.Constant) and isinstance(value.value, str):
                if any(SECRET_NAME_RE.search(n) for n in names) \
                        and not PLACEHOLDER_RE.match(value.value):
                    add(node, "SEC001",
                        f"literal value assigned to '{names[0]}'")

        # --- keyword arguments such as connect(password="hunter2") ------------
        if isinstance(node, ast.Call):
            for kw in node.keywords:
                if kw.arg and SECRET_NAME_RE.search(kw.arg) \
                        and isinstance(kw.value, ast.Constant) \
                        and isinstance(kw.value.value, str) \
                        and not PLACEHOLDER_RE.match(kw.value.value):
                    add(node, "SEC001", f"literal value in argument '{kw.arg}'")

    return findings, used


# --------------------------------------------------------------------------
# R tokeniser
# --------------------------------------------------------------------------

R_IDENT_RE = re.compile(r"[A-Za-z.][A-Za-z0-9._]*")
R_RAW_RE = re.compile(r"[rR](['\"])(-*)([\[({])")
R_MULTI_OPS = ("<<-", "->>", "<-", "->", "::", ":::", "==", "!=", "<=", ">=", "&&", "||", "|>")


@dataclass
class RTok:
    kind: str      # STR | IDENT | OP
    value: str
    line: int
    col: int


def tokenize_r(src: str) -> list[RTok]:
    """Small, string- and comment-aware tokeniser for R source code.

    Not a full parser, but enough to avoid matching inside comments or regex
    strings -- the classic pitfall of scanning raw text with a regex.
    """
    toks: list[RTok] = []
    i, n = 0, len(src)
    line, line_start = 1, 0

    def advance(end: int) -> None:
        nonlocal line, line_start
        seg = src[i:end]
        nl = seg.count("\n")
        if nl:
            line += nl
            line_start = i + seg.rfind("\n") + 1

    while i < n:
        ch = src[i]
        col = i - line_start + 1

        if ch == "\n":
            line += 1
            i += 1
            line_start = i
            continue
        if ch in " \t\r":
            i += 1
            continue
        if ch == "#":
            j = src.find("\n", i)
            i = n if j == -1 else j
            continue

        # raw string: r"(...)", R'[---[...]---]'
        m = R_RAW_RE.match(src, i)
        if m:
            quote, dashes, opener = m.group(1), m.group(2), m.group(3)
            closer = {"(": ")", "[": "]", "{": "}"}[opener]
            end_marker = closer + dashes + quote
            j = src.find(end_marker, m.end())
            end = n if j == -1 else j + len(end_marker)
            toks.append(RTok("STR", src[m.end():(j if j != -1 else n)], line, col))
            advance(end)
            i = end
            continue

        # ordinary string
        if ch in "\"'":
            quote = ch
            j = i + 1
            buf: list[str] = []
            while j < n:
                c = src[j]
                if c == "\\" and j + 1 < n:
                    esc = src[j + 1]
                    buf.append({"n": "\n", "t": "\t", "\\": "\\"}.get(esc, esc))
                    j += 2
                    continue
                if c == quote:
                    break
                buf.append(c)
                j += 1
            end = min(j + 1, n)
            toks.append(RTok("STR", "".join(buf), line, col))
            advance(end)
            i = end
            continue

        # backtick identifier
        if ch == "`":
            j = src.find("`", i + 1)
            end = n if j == -1 else j + 1
            toks.append(RTok("IDENT", src[i + 1:(j if j != -1 else n)], line, col))
            advance(end)
            i = end
            continue

        # %in%, %>%, %||%
        if ch == "%":
            j = src.find("%", i + 1)
            end = n if j == -1 else j + 1
            toks.append(RTok("OP", src[i:end], line, col))
            i = end
            continue

        m = R_IDENT_RE.match(src, i)
        if m:
            toks.append(RTok("IDENT", m.group(0), line, col))
            i = m.end()
            continue

        for op in R_MULTI_OPS:
            if src.startswith(op, i):
                toks.append(RTok("OP", op, line, col))
                i += len(op)
                break
        else:
            toks.append(RTok("OP", ch, line, col))
            i += 1

    return toks


R_ENV_GETTERS = {"Sys.getenv"}
R_CHDIR = {"setwd"}


def check_r(source: str, relpath: str, lines: list[str], cfg: Config,
            line_offset: int = 0) -> tuple[list[Finding], dict[str, tuple]]:
    findings: list[Finding] = []
    used: dict[str, tuple] = {}
    toks = tokenize_r(source)

    def add(tok: RTok, code: str, msg: str) -> None:
        line = tok.line + line_offset
        if 0 < line <= len(lines) and SUPPRESS_RE.search(lines[line - 1]):
            return
        findings.append(Finding(relpath, line, tok.col, code, msg))

    seen_setenv: set[int] = set()

    def peek(idx: int, offset: int) -> RTok | None:
        j = idx + offset
        return toks[j] if 0 <= j < len(toks) else None

    for k, tok in enumerate(toks):
        if tok.kind == "STR":
            val = tok.value
            if CONN_STRING_RE.search(val):
                add(tok, "SEC002", "connection string with embedded credentials")
            elif ODBC_RE.search(val) and "=" in val and ";" in val:
                add(tok, "SEC002", "ODBC-style connection string containing a password")
            elif ABS_PATH_RE.match(val) and looks_like_path(val) and not is_allowed_path(val, cfg):
                add(tok, "ABS001", f"absolute path in code: {val!r}")
            continue

        if tok.kind != "IDENT":
            continue

        nxt, nxt2 = peek(k, 1), peek(k, 2)

        # Sys.getenv("KEY")
        if tok.value in R_ENV_GETTERS or tok.value in set(cfg["env_getters"]):
            if nxt and nxt.kind == "OP" and nxt.value == "(" and nxt2:
                if nxt2.kind == "STR":
                    used.setdefault(nxt2.value,
                                    (relpath, nxt2.line + line_offset, nxt2.col))
                elif nxt2.kind == "OP" and nxt2.value == ")":
                    add(tok, "ENV003", "Sys.getenv() without a name returns the whole environment")
                else:
                    add(tok, "ENV003", "environment variable with a non-constant name")
            continue

        # Sys.setenv(KEY = "value")
        if tok.value == "Sys.setenv" and nxt and nxt.value == "(":
            j = k + 2
            while j + 2 < len(toks) and toks[j].kind == "IDENT":
                name, eq, val = toks[j], toks[j + 1], toks[j + 2]
                if eq.kind == "OP" and eq.value == "=" and val.kind == "STR" \
                        and SECRET_NAME_RE.search(name.value) \
                        and not PLACEHOLDER_RE.match(val.value):
                    add(name, "SEC001", f"literal value assigned to '{name.value}'")
                    seen_setenv.add(id(name))
                j += 4  # name = value ,
            continue

        if tok.value in R_CHDIR and nxt and nxt.value == "(":
            add(tok, "ABS002", "setwd() hard-codes the working directory")
            continue

        # secret <- "..." / secret = "..."
        if id(tok) in seen_setenv:
            continue
        if SECRET_NAME_RE.search(tok.value) and nxt and nxt.kind == "OP":
            if nxt.value in ("<-", "<<-", "=") and nxt2 and nxt2.kind == "STR" \
                    and not PLACEHOLDER_RE.match(nxt2.value):
                add(tok, "SEC001", f"literal value assigned to '{tok.value}'")

    return findings, used


# --------------------------------------------------------------------------
# File formats
# --------------------------------------------------------------------------

RMD_CHUNK_RE = re.compile(r"^[ \t]*```+\s*\{\s*[rR][ ,}]", re.MULTILINE)
RMD_FENCE_END_RE = re.compile(r"^[ \t]*```+\s*$", re.MULTILINE)


def extract_rmd_chunks(text: str) -> list[tuple[str, int]]:
    """Extracts R chunks from .Rmd/.qmd. Returns (source, line offset)."""
    chunks: list[tuple[str, int]] = []
    lines = text.splitlines()
    inside = False
    start = 0
    buf: list[str] = []
    for idx, line in enumerate(lines):
        if not inside and RMD_CHUNK_RE.match(line + "\n"):
            inside, start, buf = True, idx + 1, []
            continue
        if inside and RMD_FENCE_END_RE.match(line + "\n"):
            chunks.append(("\n".join(buf), start))
            inside = False
            continue
        if inside:
            buf.append(line)
    if inside and buf:
        chunks.append(("\n".join(buf), start))
    return chunks


def extract_notebook_cells(text: str) -> list[tuple[str, int]]:
    """Extracts code cells from .ipynb. Line numbers are per cell, offset 0."""
    try:
        doc = json.loads(text)
    except json.JSONDecodeError:
        return []
    cells = []
    for i, cell in enumerate(doc.get("cells", [])):
        if cell.get("cell_type") != "code":
            continue
        src = cell.get("source", [])
        code = "".join(src) if isinstance(src, list) else str(src)
        if code.strip():
            cells.append((code, i))
    return cells


def check_file(path: Path, cfg: Config) -> tuple[list[Finding], dict[str, tuple]]:
    rel = str(path.relative_to(cfg.root)) if path.is_absolute() else str(path)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return [Finding(rel, 1, 1, "IO001", f"cannot read file: {exc}")], set()

    lines = text.splitlines()
    suffix = path.suffix.lower()
    findings: list[Finding] = []
    used: dict[str, tuple] = {}

    if suffix == ".py":
        findings, used = check_python(text, rel, lines, cfg)
    elif suffix == ".ipynb":
        for code, cell_idx in extract_notebook_cells(text):
            f, u = check_python(code, f"{rel}[cel {cell_idx}]", code.splitlines(), cfg)
            findings += f
            for k, v in u.items():
                used.setdefault(k, v)
    elif suffix in (".r",):
        findings, used = check_r(text, rel, lines, cfg)
    elif suffix in (".rmd", ".qmd"):
        for code, offset in extract_rmd_chunks(text):
            f, u = check_r(code, rel, lines, cfg, line_offset=offset)
            findings += f
            for k, v in u.items():
                used.setdefault(k, v)
    return findings, used


# --------------------------------------------------------------------------
# .env.example
# --------------------------------------------------------------------------

ENV_LINE_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")


def parse_env_example(path: Path) -> tuple[dict[str, int], list[Finding]]:
    keys: dict[str, int] = {}
    findings: list[Finding] = []
    if not path.is_file():
        return keys, findings
    # utf-8-sig strips a BOM, which Windows editors add and which would
    # otherwise hide the first key in the file.
    for lineno, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = ENV_LINE_RE.match(line)
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip().strip("\"'")
        keys.setdefault(key, lineno)
        if SECRET_ENVNAME_RE.search(key) and raw and not PLACEHOLDER_RE.match(raw):
            findings.append(Finding(path.name, lineno, 1, "SEC003",
                                    f"'{key}' appears to hold a real value "
                                    f"rather than a placeholder"))
    return keys, findings


# --------------------------------------------------------------------------
# Collecting files
# --------------------------------------------------------------------------

def iter_project_files(cfg: Config):
    ignore = set(cfg["ignore_dirs"])
    exts = {e.lower() for e in cfg["extensions"]}
    for dirpath, dirnames, filenames in os.walk(cfg.root):
        dirnames[:] = [d for d in dirnames if d not in ignore and not d.startswith(".git")]
        for name in filenames:
            p = Path(dirpath) / name
            if p.suffix.lower() in exts:
                yield p


def check_forbidden_files(cfg: Config) -> list[Finding]:
    findings = []
    ignore = set(cfg["ignore_dirs"])
    forbidden = set(cfg["forbidden_files"])
    for dirpath, dirnames, filenames in os.walk(cfg.root):
        dirnames[:] = [d for d in dirnames if d not in ignore and not d.startswith(".git")]
        for name in filenames:
            if name in forbidden:
                rel = str((Path(dirpath) / name).relative_to(cfg.root))
                findings.append(Finding(rel, 1, 1, "FILE001",
                                        "this file does not belong in the repository"))
    return findings


def is_ignored_path(rel: str, cfg: Config) -> bool:
    return any(rel == p or rel.startswith(p.rstrip("/") + "/") for p in cfg["ignore_paths"])


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Checks Python and R code for absolute paths and environment usage.")
    parser.add_argument("paths", nargs="*", type=Path,
                        help="files to check (empty = whole project)")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="project root")
    parser.add_argument("--config", type=Path, default=None, help="path to .envcheck.toml")
    parser.add_argument("--check-unused", action="store_true",
                        help="scan the whole project and report unused keys from .env.example")
    parser.add_argument("--json", action="store_true", help="emit findings as JSON")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    if not root.is_dir():
        print(f"envcheck: project root does not exist: {root}", file=sys.stderr)
        return 2

    cfg = load_config(root, args.config)
    env_keys, findings = parse_env_example(root / cfg["env_example"])

    if args.paths:
        targets = [p.resolve() for p in args.paths
                   if p.suffix.lower() in {e.lower() for e in cfg["extensions"]}]
    else:
        targets = list(iter_project_files(cfg))

    used_here: dict[str, tuple] = {}
    for path in targets:
        try:
            rel = str(path.resolve().relative_to(root))
        except ValueError:
            rel = str(path)
        if is_ignored_path(rel, cfg):
            continue
        f, u = check_file(path, cfg)
        findings += f
        for k, v in u.items():
            used_here.setdefault(k, v)

    optional = set(cfg["env_vars_optional"])

    # ENV001: used but undocumented. Reported at the first usage site, which is
    # more actionable than pointing at the .env.example file itself.
    for key in sorted(set(used_here) - set(env_keys) - optional):
        loc_path, loc_line, loc_col = used_here[key]
        findings.append(Finding(loc_path, loc_line, loc_col, "ENV001",
                                f"'{key}' is used but is not listed in "
                                f"{cfg['env_example']}"))

    if args.check_unused:
        used_all = set(used_here)
        if args.paths:  # rescan the whole project so the verdict is fair
            for path in iter_project_files(cfg):
                rel = str(path.relative_to(root))
                if is_ignored_path(rel, cfg):
                    continue
                _, u = check_file(path, cfg)
                used_all |= set(u)
        for key in sorted(set(env_keys) - used_all - optional):
            findings.append(Finding(cfg["env_example"], env_keys[key], 1, "ENV002",
                                    f"'{key}' is listed in {cfg['env_example']} but is "
                                    f"never used"))
        findings += check_forbidden_files(cfg)

    seen: set[tuple] = set()
    unique: list[Finding] = []
    for f in findings:
        sig = (f.path, f.line, f.col, f.code, f.message)
        if sig not in seen:
            seen.add(sig)
            unique.append(f)
    findings = unique
    findings.sort(key=lambda f: (f.path, f.line, f.col, f.code))

    if args.json:
        print(json.dumps([f.__dict__ for f in findings], indent=2, ensure_ascii=False))
    else:
        for f in findings:
            print(f.render())
        if findings:
            counts: dict[str, int] = {}
            for f in findings:
                counts[f.code] = counts.get(f.code, 0) + 1
            summary = ", ".join(f"{c}: {n}" for c, n in sorted(counts.items()))
            print(f"\nenvcheck: {len(findings)} finding(s) -- {summary}", file=sys.stderr)
        else:
            print(f"envcheck: clean ({len(targets)} file(s) checked)")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
