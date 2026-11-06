#!/usr/bin/env python3
"""PreToolUse guard that turns the hard rules in AGENTS.md into checks.

Claude Code pipes the pending tool call to stdin as JSON. This script answers
with a permission decision:

- deny: the call would bypass a quality gate (skip the git hook, grow the lint
  baseline, hand-edit a generated contract, ...). The agent has to fix the
  cause instead.
- ask: the call acts outside the repository or on CI and needs the
  maintainer's explicit approval (push to main, merge, release, edit workflows).

Anything else exits silently and the normal permission flow applies.
Tests: python3 -m unittest discover -s .claude/hooks
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys

BASELINE = ".swiftlint-baseline.json"
ALLOWLIST = "scripts/unused-code-allowlist.txt"

# Written by `npm run schema` in services/compatibility; never by hand.
GENERATED = {
    "contracts/service-constants.json",
    "contracts/compatibility-policy.example.json",
    "Sources/FanBar/Resources/mac-model-names.json",
    "services/compatibility/web/src/lib/mac-model-names.json",
}

# Editing these changes how every change is checked; the maintainer decides.
GATE_PREFIXES = (".github/workflows/", ".githooks/", ".claude/hooks/")
GATE_FILES = {
    ".claude/settings.json",
    ".swiftlint.yml",
    ".swiftformat",
    "scripts/pre-commit.sh",
    "scripts/install-git-hooks.sh",
    "scripts/coverage-report.py",
    "scripts/find-unused-code.py",
    "scripts/ci-swift-relevant.sh",
}

PROTECTED_FOR_SHELL_WRITES = sorted(GENERATED | {BASELINE, ALLOWLIST})


def project_root() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def relative(path: str, root: str) -> str:
    absolute = os.path.normpath(path if os.path.isabs(path) else os.path.join(root, path))
    rel = os.path.relpath(absolute, os.path.normpath(root))
    return rel.replace(os.sep, "/")


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return ""


def proposed_content(tool: str, tool_input: dict, current: str) -> str | None:
    """The file's content after the edit, or None when it can't be derived."""
    if tool == "Write":
        return tool_input.get("content", "")
    edits = tool_input.get("edits")
    if tool == "MultiEdit" and isinstance(edits, list):
        pending = edits
    elif tool == "Edit":
        pending = [tool_input]
    else:
        return None
    content = current
    for edit in pending:
        old, new = edit.get("old_string", ""), edit.get("new_string", "")
        if edit.get("replace_all"):
            content = content.replace(old, new)
        else:
            content = content.replace(old, new, 1)
    return content


def baseline_entries(text: str) -> int:
    try:
        data = json.loads(text) if text.strip() else []
    except ValueError:
        return -1
    return len(data) if isinstance(data, list) else -1


def allowlist_entries(text: str) -> int:
    return sum(1 for line in text.splitlines() if line.split("#", 1)[0].strip())


def check_file_edit(tool: str, tool_input: dict, root: str) -> tuple[str, str] | None:
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not path:
        return None
    rel = relative(path, root)
    if rel.startswith("../"):
        return None
    current = read(os.path.join(root, rel))
    after = proposed_content(tool, tool_input, current)

    if rel in GENERATED:
        return ("deny", f"{rel} is generated. Change services/compatibility/src/policy.ts or "
                        "contracts/mac-model-names.json, then run `npm run schema` in services/compatibility.")

    if rel == BASELINE:
        if after is None or baseline_entries(after) < 0 or baseline_entries(after) > baseline_entries(current):
            return ("deny", "The SwiftLint baseline may only shrink. Fix the new violation instead, or shrink "
                            "the baseline with `swiftlint lint --write-baseline` after paying down debt.")
        return None

    if rel == ALLOWLIST:
        if after is None or allowlist_entries(after) > allowlist_entries(current):
            return ("deny", "Do not grow scripts/unused-code-allowlist.txt to hide a finding. "
                            "Remove the unused code, or ask the maintainer.")
        return None

    if rel.endswith(".swift") and rel.startswith(("Sources/", "Tests/")) and after is not None:
        if after.count("swiftlint:disable") > current.count("swiftlint:disable"):
            return ("deny", "New `swiftlint:disable` markers are not allowed. Split the function or type, "
                            "or fix the violation.")

    if rel in GATE_FILES or rel.startswith(GATE_PREFIXES):
        return ("ask", f"{rel} controls how changes are checked. AGENTS.md: never change checks or "
                       "workflows to get a change merged. Approve only if this is the intended change.")
    return None


def split_commands(command: str) -> list[list[str]]:
    """Split a shell line into simple commands, each as a token list."""
    parts = re.split(r"&&|\|\||;|\||\n|\$\(|`", command)
    commands = []
    for part in parts:
        try:
            tokens = shlex.split(part, comments=True)
        except ValueError:
            tokens = part.split()
        while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
            tokens = tokens[1:]  # leading VAR=value assignments
        if tokens and tokens[0] in {"sudo", "env", "command", "exec", "time", "nohup"}:
            tokens = tokens[1:]
        if tokens:
            commands.append(tokens)
    return commands


def git_subcommand(tokens: list[str]) -> tuple[str, list[str], list[str]]:
    """For `git [-c k=v] [-C dir] sub args`, return (sub, args, global options)."""
    index, options = 1, []
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        options.append(option)
        if option in {"-c", "-C", "--git-dir", "--work-tree"} and index + 1 < len(tokens):
            options.append(tokens[index + 1])
            index += 1
        index += 1
    if index >= len(tokens):
        return "", [], options
    return tokens[index], tokens[index + 1:], options


def check_git(tokens: list[str]) -> tuple[str, str] | None:
    sub, args, options = git_subcommand(tokens)
    overrides = [options[i + 1] for i, o in enumerate(options[:-1]) if o == "-c"]
    if any(o.lower().startswith("core.hookspath") for o in overrides):
        return ("deny", "Do not override core.hooksPath; the .githooks pre-commit hook must run.")

    if sub in {"commit", "push", "merge", "rebase", "cherry-pick", "am"}:
        if "--no-verify" in args or (sub == "commit" and any(re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", a) for a in args)):
            return ("deny", "AGENTS.md: never commit or push with --no-verify. Fix what the hook reports.")

    if sub == "config":
        lowered = [a.lower() for a in args]
        if "core.hookspath" in lowered:
            value_index = lowered.index("core.hookspath") + 1
            value = args[value_index] if value_index < len(args) else None
            unsets = any(a.startswith("--unset") for a in args)
            if unsets or (value is not None and value != ".githooks"):
                return ("deny", "core.hooksPath must stay `.githooks`. Run `zsh scripts/install-git-hooks.sh` "
                                "if it is wrong.")

    if sub == "push":
        refs = [a for a in args if not a.startswith("-")][1:]
        to_main = any(re.search(r"(^|:)(refs/heads/)?main$", ref) for ref in refs)
        tags = "--tags" in args or "--follow-tags" in args or any(
            re.search(r"(^|:)(refs/tags/)?v\d", ref) for ref in refs)
        forced = any(a in {"-f", "--force"} or a.startswith("--force-with-lease") for a in args)
        if to_main:
            return ("ask", "Pushing to main. main is protected; changes land through a pull request.")
        if tags:
            return ("ask", "Pushing a release tag publishes a release. Only the maintainer releases.")
        if forced:
            return ("ask", "Force push rewrites shared history. Confirm the branch is yours.")

    if sub == "tag" and any(re.fullmatch(r"v\d[\w.\-]*", a) for a in args):
        return ("ask", "Release tags are the maintainer's job (docs/releasing.md).")
    return None


def check_gh(tokens: list[str]) -> tuple[str, str] | None:
    words = [t for t in tokens[1:] if not t.startswith("-")]
    joined = " ".join(words[:2])
    if joined in {"pr merge", "release create", "release upload", "release edit", "release delete"}:
        return ("ask", f"`gh {joined}` acts on GitHub for everyone. AGENTS.md requires the maintainer's "
                       "explicit approval.")
    if joined in {"pr comment", "pr review", "issue comment", "issue close", "pr close"}:
        return ("ask", f"`gh {joined}` posts publicly. AGENTS.md requires the maintainer's approval.")
    if words[:1] == ["api"] and any("protection" in t or "rulesets" in t for t in tokens):
        return ("deny", "Never change branch protection or rulesets from an agent session.")
    if words[:2] in (["secret", "set"], ["variable", "set"], ["workflow", "run"], ["workflow", "disable"]):
        return ("ask", f"`gh {joined}` changes repository settings or CI. Approve explicitly.")
    return None


def check_bash(command: str) -> tuple[str, str] | None:
    for tokens in split_commands(command):
        program = os.path.basename(tokens[0])
        if program == "git":
            verdict = check_git(tokens)
        elif program == "gh":
            verdict = check_gh(tokens)
        elif program == "swiftlint" and "--write-baseline" in tokens:
            verdict = ("ask", "Rewriting the SwiftLint baseline is only allowed to shrink it. Confirm no new "
                              "violation is being frozen.")
        elif any(t.endswith("release-local.sh") or t.endswith("notarize-dmg.sh") for t in tokens):
            verdict = ("ask", "Publishing and notarizing are the maintainer's job (docs/releasing.md).")
        elif program in {"npm", "npx", "wrangler"} and ("deploy" in tokens or "wrangler deploy" in command) \
                and "--dry-run" not in tokens:
            verdict = ("ask", "Deploying the compatibility service affects production. Use `npm run dry-run` "
                              "unless the maintainer asked for a deploy.")
        else:
            verdict = None
        if verdict:
            return verdict

    # Shell writes that would sidestep the file checks above.
    for path in PROTECTED_FOR_SHELL_WRITES:
        if path not in command:
            continue
        redirected = re.search(rf">>?\s*[\"']?(\./)?{re.escape(path)}", command)
        written = False
        for tokens in split_commands(command):
            program = os.path.basename(tokens[0])
            targets = [t[2:] if t.startswith("./") else t for t in tokens[1:]]
            if path not in targets:
                continue
            in_place = program in {"sed", "perl"} and any(re.fullmatch(r"-[A-Za-z]*i.*", t) for t in tokens[1:])
            if in_place or program in {"tee", "rm", "truncate"} or (program in {"cp", "mv"} and targets[-1] == path):
                written = True
        if redirected or written:
            return ("deny", f"Do not modify {path} from the shell. Use the generator or the Edit tool so "
                            "the guard can check the change.")
    return None


def decide(payload: dict) -> tuple[str, str] | None:
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if tool == "Bash":
        return check_bash(tool_input.get("command", ""))
    if tool in {"Edit", "Write", "MultiEdit", "NotebookEdit"}:
        return check_file_edit(tool, tool_input, project_root())
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    verdict = decide(payload)
    if verdict is None:
        return 0
    decision, reason = verdict
    json.dump({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": f"[FanBar agent guard] {reason}",
        }
    }, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
