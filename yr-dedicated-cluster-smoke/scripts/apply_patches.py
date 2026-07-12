#!/usr/bin/env python3.11
"""Deploy-side adaptations for the rust functionsystem under the Python yrexp CLI.
Run ON each cluster node AFTER pip-installing the wheels and staging config.toml.

DEFAULT (rust-fixed packages): only the runtime-path symlinks (a packaging-layout
bridge, NOT a CLI change). The three CLI-arg mismatches are now fixed IN THE RUST
SOURCE (functionsystem rust-rewrite), so the stock Python CLI config works as-is:
  - function_proxy duplicate cache_storage/data_system flags -> clap `overrides_with`
    (function_proxy/src/config.rs)
  - function_agent unknown --RUNTIME_METRICS_CONFIG -> added to legacy-ignore list
    (common/utils/src/cli_compat.rs FUNCTION_AGENT)
  - empty datasystem host ":31501" -> runtime_manager falls back to node host
    (runtime_manager/src/executor.rs build_runtime_env)

LEGACY (pre-fix packages, e.g. build #32 / 566f6f6): pass --legacy-cli-patches to
ALSO patch the installed config.toml.jinja / config.toml. Idempotent; keeps .orig.

Usage:  python3.11 apply_patches.py [--legacy-cli-patches]
"""
import os, re, shutil, site, sys

SP = os.path.join(site.getsitepackages()[0], "yr")
JINJA = os.path.join(SP, "cli", "config.toml.jinja")
CONFIG = "/home/disk/yr-workspace/config.toml"
LEGACY = "--legacy-cli-patches" in sys.argv

def backup(p):
    if os.path.exists(p) and not os.path.exists(p + ".orig"):
        shutil.copy(p, p + ".orig")

def section_filter(path, section, drop_prefixes):
    if not os.path.exists(path):
        print(f"  SKIP {path} (missing)"); return
    backup(path)
    out, sec, removed = [], None, []
    for line in open(path).read().splitlines(keepends=True):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"): sec = s
        if sec == section and any(s.startswith(p) for p in drop_prefixes):
            removed.append(s[:48]); continue
        out.append(line)
    open(path, "w").write("".join(out))
    print(f"  {path} [{section}] removed: {removed or 'none'}")

def section_add_after(path, section, anchor_prefix, new_line):
    if not os.path.exists(path):
        print(f"  SKIP {path} (missing)"); return
    text = open(path).read()
    key = new_line.split("=")[0].strip()
    blk = re.search(r'\[' + re.escape(section.strip('[]')) + r'\](.*?)(?:\n\[|\Z)', text, re.S)
    if blk and re.search(r'(?m)^\s*' + re.escape(key) + r'\s*=', blk.group(1)):
        print(f"  {path} [{section}] {key}: already present"); return
    backup(path)
    out, sec, done = [], None, False
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"): sec = s
        out.append(line)
        if sec == section and s.startswith(anchor_prefix) and not done:
            out.append(new_line if new_line.endswith("\n") else new_line + "\n"); done = True
    open(path, "w").write("".join(out))
    print(f"  {path} [{section}] added {key}: {'ok' if done else 'ANCHOR NOT FOUND'}")

def symlink(target, link):
    os.makedirs(os.path.dirname(link), exist_ok=True)
    if os.path.islink(link) or os.path.exists(link):
        try: os.remove(link)
        except IsADirectoryError: shutil.rmtree(link)
    os.symlink(target, link)
    print(f"  symlink {link} -> {target} : {'OK' if os.path.exists(link) else 'FAILED'}")

print("== runtime path symlinks (wheel installs python at yr/main, cpp at yr/cpp) ==")
symlink(SP, os.path.join(SP, "runtime", "service", "python", "yr"))
symlink(os.path.join(SP, "cpp"), os.path.join(SP, "runtime", "service", "cpp"))

if LEGACY:
    print("== [legacy] CLI-config patches (only for packages BEFORE the rust fix) ==")
    section_filter(JINJA, "[function_proxy.args]", ("data_system_host", "data_system_port"))
    section_add_after(JINJA, "[function_agent.args]", "data_system_port",
                      'data_system_host = "{{ values.ds_worker.ip }}"')
    section_filter(CONFIG, "[function_agent.args]", ("RUNTIME_METRICS_CONFIG",))
else:
    print("== CLI-arg mismatches handled in rust source; no CLI/config patching ==")

print("== verify ==")
print("  python runtime entry:", "OK" if os.path.exists(os.path.join(SP,"runtime/service/python/yr/main/yr_runtime_main.py")) else "MISSING")
print("  cpp runtime bin:", "OK" if os.path.exists(os.path.join(SP,"runtime/service/cpp/bin/runtime")) else "MISSING")
print("DONE")
