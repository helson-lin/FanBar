"""Tests for agent_guard.py. Run: python3 -m unittest discover -s .claude/hooks"""

import json
import os
import tempfile
import unittest

import agent_guard


def bash(command):
    return agent_guard.decide({"tool_name": "Bash", "tool_input": {"command": command}})


def decision(verdict):
    return verdict[0] if verdict else None


class BashTests(unittest.TestCase):
    def test_skipping_the_hook_is_denied(self):
        for command in [
            "git commit --no-verify -m x",
            "git commit -nm x",
            "git -c core.hooksPath=/dev/null commit -m x",
            "git push --no-verify origin feat/x",
            "git config --unset core.hooksPath",
            "git config core.hooksPath /tmp/none",
            "cd repo && git commit -n -m x",
        ]:
            self.assertEqual(decision(bash(command)), "deny", command)

    def test_normal_git_work_passes(self):
        for command in [
            "git status",
            "git commit -m 'fix: keep -n in message'",
            "git config core.hooksPath .githooks",
            "git config --get core.hooksPath",
            "git push -u origin docs/agents-md",
            "git tag --list",
            "git log --oneline -5 main",
        ]:
            self.assertIsNone(bash(command), command)

    def test_actions_outside_the_repo_ask(self):
        for command in [
            "git push origin main",
            "git push origin HEAD:main",
            "git push origin v0.7.3",
            "git push --tags",
            "git push --force origin feat/x",
            "git tag -a v0.7.3 -m 'FanBar 0.7.3'",
            "gh pr merge 128 --squash",
            "gh release create v0.7.3",
            "gh pr comment 12 --body hi",
            "FANBAR_NOTARY_PROFILE=x zsh scripts/release-local.sh",
            "cd services/compatibility && npm run deploy",
            "swiftlint lint --write-baseline .swiftlint-baseline.json",
        ]:
            self.assertEqual(decision(bash(command)), "ask", command)

    def test_branch_protection_is_denied(self):
        self.assertEqual(decision(bash("gh api -X PUT repos/o/r/branches/main/protection")), "deny")

    def test_dry_runs_and_reads_pass(self):
        for command in [
            "cd services/compatibility && npm run dry-run",
            "gh pr view 128",
            "gh pr create --title x --body y",
            "cat contracts/service-constants.json",
            "cat contracts/service-constants.json > /tmp/copy.json",
            "cd services/compatibility && npm run schema",
        ]:
            self.assertIsNone(bash(command), command)

    def test_shell_writes_to_guarded_files_are_denied(self):
        for command in [
            "echo '{}' > contracts/service-constants.json",
            "sed -i '' 's/a/b/' scripts/unused-code-allowlist.txt",
            "echo Foo >> scripts/unused-code-allowlist.txt",
            "cp /tmp/x.json ./.swiftlint-baseline.json",
        ]:
            self.assertEqual(decision(bash(command)), "deny", command)


class EditTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        os.environ["CLAUDE_PROJECT_DIR"] = self.root
        os.makedirs(os.path.join(self.root, "scripts"))
        os.makedirs(os.path.join(self.root, "Sources/FanBar"))
        self.write(".swiftlint-baseline.json", json.dumps([{"a": 1}, {"b": 2}]))
        self.write("scripts/unused-code-allowlist.txt", "# header\nFanBarApp  # entry\nOther\n")
        self.write("Sources/FanBar/Thing.swift", "struct Thing {}\n")

    def write(self, rel, text):
        with open(os.path.join(self.root, rel), "w", encoding="utf-8") as handle:
            handle.write(text)

    def edit(self, tool, rel, **fields):
        fields["file_path"] = os.path.join(self.root, rel)
        return agent_guard.decide({"tool_name": tool, "tool_input": fields})

    def test_baseline_may_shrink_but_not_grow(self):
        self.assertIsNone(self.edit("Write", ".swiftlint-baseline.json", content=json.dumps([{"a": 1}])))
        grown = json.dumps([{"a": 1}, {"b": 2}, {"c": 3}])
        self.assertEqual(decision(self.edit("Write", ".swiftlint-baseline.json", content=grown)), "deny")

    def test_allowlist_may_shrink_but_not_grow(self):
        self.assertIsNone(self.edit("Edit", "scripts/unused-code-allowlist.txt",
                                    old_string="Other\n", new_string=""))
        self.assertEqual(decision(self.edit("Edit", "scripts/unused-code-allowlist.txt",
                                            old_string="Other\n", new_string="Other\nNewThing\n")), "deny")
        self.assertIsNone(self.edit("Edit", "scripts/unused-code-allowlist.txt",
                                    old_string="# header", new_string="# header, reworded"))

    def test_new_swiftlint_disable_is_denied(self):
        verdict = self.edit("Edit", "Sources/FanBar/Thing.swift", old_string="struct Thing {}",
                            new_string="// swiftlint:disable:next type_name\nstruct Thing {}")
        self.assertEqual(decision(verdict), "deny")
        self.assertIsNone(self.edit("Edit", "Sources/FanBar/Thing.swift", old_string="struct Thing {}",
                                    new_string="struct Thing { let id = 1 }"))

    def test_generated_contracts_are_denied(self):
        for rel in ["contracts/service-constants.json", "Sources/FanBar/Resources/mac-model-names.json"]:
            self.assertEqual(decision(self.edit("Write", rel, content="{}")), "deny", rel)
        self.assertIsNone(self.edit("Write", "contracts/mac-model-names.json", content="{}"))

    def test_quality_gates_ask(self):
        for rel in [".github/workflows/quality.yml", ".githooks/pre-commit", ".claude/settings.json",
                    ".claude/hooks/agent_guard.py", "scripts/coverage-report.py"]:
            self.assertEqual(decision(self.edit("Write", rel, content="x")), "ask", rel)

    def test_ordinary_files_pass(self):
        self.assertIsNone(self.edit("Write", "AGENTS.md", content="x"))
        self.assertIsNone(self.edit("Write", "/tmp/elsewhere.txt", content="x"))


if __name__ == "__main__":
    unittest.main()
