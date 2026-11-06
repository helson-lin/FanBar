#!/bin/zsh
# Enables the repository's git hooks (.githooks/) for this clone.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x .githooks/* scripts/pre-commit.sh scripts/find-unused-code.py
print "Git hooks enabled: .githooks/pre-commit runs scripts/pre-commit.sh before every commit."
