#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Check that JJB reads back every value scripts/write-ini.sh writes.
#
# Usage: ini-roundtrip.sh <venv-dir>
#
# Writes an update-mode ini whose credentials carry the characters that
# break naive writers, loads it with JJB's own JJBConfig from <venv-dir>,
# and compares each value with the input. Two mutants then prove the
# check has teeth: the writer with its '%' escaping removed, so
# ConfigParser interpolates, and a writer that pastes the values into
# an unquoted heredoc, so the shell expands them. Both must fail.

set -euo pipefail

venv=${1:?usage: ini-roundtrip.sh <venv-dir>}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
writer="$root/scripts/write-ini.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export INPUT_MODE=update
export INPUT_JENKINS_URL='https://jenkins.example.org/ci%20path/'
export INPUT_JENKINS_USER='jjb user;#%'
# Single quotes: the backtick, '$' and '%(...)s' are literal here. The
# U+00A0 inside the value must survive; only surrounding whitespace is
# stripped, and validate.sh rejects that.
# shellcheck disable=SC2016
export INPUT_JENKINS_PASSWORD='p%40ss $HOME `id` #not;a'$'\xc2\xa0''comment %(user)s'

# Exit 0 only if JJB reads the ini at $1 back to the exact inputs.
check() {
    PYTHONWARNINGS='ignore:pkg_resources is deprecated:UserWarning' \
        "$venv/bin/python" - "$1" <<'PY'
import os
import sys

from jenkins_jobs.config import JJBConfig

config = JJBConfig(sys.argv[1], config_file_required=True)
failed = False
for key in ("url", "user", "password"):
    want = os.environ["INPUT_JENKINS_" + key.upper()]
    if config.jenkins[key] != want:
        print(f"{key}: JJB read a different value", file=sys.stderr)
        failed = True
sys.exit(1 if failed else 0)
PY
}

expect_fail() {
    local name=$1 ini=$2
    if check "$ini" 2> "$work/$name.log"; then
        echo "::error::Mutant '$name' passed; the check is too weak" >&2
        exit 1
    fi
    echo "Mutant '$name' rejected ✅"
}

# The real writer: values must round-trip and the file must be private.
bash "$writer" "$work/real.ini"
mode=$(stat -c '%a' "$work/real.ini")
if [ "$mode" != 600 ]; then
    echo "::error::ini has mode $mode, not 600" >&2
    exit 1
fi
check "$work/real.ini"
echo "Values round-trip through JJB ✅"

# Mutant 1: no '%' escaping, so ConfigParser interpolates.
sed 's|//%/%%}|}|' "$writer" > "$work/interpolated.sh"
if cmp -s "$writer" "$work/interpolated.sh"; then
    echo "::error::Could not build the interpolation mutant" >&2
    exit 1
fi
bash "$work/interpolated.sh" "$work/interpolated.ini"
expect_fail interpolated "$work/interpolated.ini"

# Mutant 2: values pasted into an unquoted heredoc, as the inline steps
# this action replaces did, so the shell expands '$' and backticks.
{
    echo 'cat <<EOF'
    echo '[jenkins]'
    echo "url=${INPUT_JENKINS_URL//%/%%}"
    echo "user=${INPUT_JENKINS_USER//%/%%}"
    echo "password=${INPUT_JENKINS_PASSWORD//%/%%}"
    echo 'EOF'
} > "$work/expanded.sh"
bash "$work/expanded.sh" > "$work/expanded.ini" 2> /dev/null
expect_fail expanded "$work/expanded.ini"
