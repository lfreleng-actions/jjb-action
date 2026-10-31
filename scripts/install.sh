#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Install Jenkins Job Builder into an isolated virtual environment.
#
# Usage: install.sh <python> <venv-dir>
#
# Installs exactly the hash-locked set in requirements.txt: binary
# wheels only, so no build backend is fetched unpinned, and no
# dependency resolution, so nothing outside the lock is added. pip
# itself is the copy the pinned interpreter bundles; it is not
# upgraded. Python runs isolated (-I), so a venv.py or pip.py in the
# working directory, or PYTHONPATH, cannot stand in for the installer.

set -euo pipefail

python=${1:?usage: install.sh <python> <venv-dir>}
venv=${2:?usage: install.sh <python> <venv-dir>}
lock="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/requirements.txt"

rm -rf "$venv"
"$python" -I -m venv "$venv"
"$venv/bin/python" -I -m pip install \
    --disable-pip-version-check \
    --no-input \
    --no-cache-dir \
    --isolated \
    --no-deps \
    --require-hashes \
    --only-binary ':all:' \
    --requirement "$lock"
"$venv/bin/jenkins-jobs" --version
