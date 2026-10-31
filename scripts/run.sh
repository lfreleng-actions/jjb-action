#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Run Jenkins Job Builder in test or update mode.
#
# Usage: run.sh <venv-dir>
#
# Expects the inputs in INPUT_* environment variables, already checked
# by validate.sh, and RUNNER_TEMP and GITHUB_OUTPUT from the runner.
# The ini file holding the credentials lives in a private directory
# under RUNNER_TEMP and is removed on every exit path.

set -euo pipefail

venv=${1:?usage: run.sh <venv-dir>}
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
jjb="$venv/bin/jenkins-jobs"

# JJB 6.5.0 imports pkg_resources, which warns on every run.
export PYTHONWARNINGS='ignore:pkg_resources is deprecated:UserWarning'

mode=$INPUT_MODE
jjb_path=$INPUT_JJB_PATH

work=$(mktemp -d "$RUNNER_TEMP/jjb-action.XXXXXX")
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

ini="$work/jenkins_jobs.ini"
bash "$script_dir/write-ini.sh" "$ini"

# JJB resolves include_path=. against the working directory.
cd "$INPUT_PATH_PREFIX"

# Generate the tree's XML into $1 and print the number of jobs JJB
# reports. JJB's log goes to stderr; it is kept to read the count, which
# JJB counts itself and which excludes views.
generate() {
    local out=$1 log="$work/generate.log" count
    local count_re='^INFO:jenkins_jobs[.]builder:'
    count_re+='Number of jobs generated: +[0-9]+$'
    if ! "$jjb" --conf "$ini" test --config-xml -o "$out" "$jjb_path" \
        2> "$log"; then
        cat "$log" >&2
        echo "::error::Jenkins Job Builder could not generate the jobs" >&2
        return 1
    fi
    cat "$log" >&2
    count=$(awk -v re="$count_re" '$0 ~ re { print $NF }' "$log")
    if ! [[ $count =~ ^[0-9]+$ ]]; then
        echo "::error::Could not read the job count from JJB's output" >&2
        return 1
    fi
    printf '%s\n' "$count"
}

if [ "$mode" = test ]; then
    output_dir=$(mktemp -d "$RUNNER_TEMP/jjb-output.XXXXXX")
    job_count=$(generate "$output_dir")
    {
        printf 'job_count=%s\n' "$job_count"
        printf 'output_dir=%s\n' "$output_dir"
    } >> "$GITHUB_OUTPUT"
    echo "Generated $job_count job(s) into $output_dir ✅"
    exit 0
fi

# Update: generate first, so a tree that is broken fails here and one
# that yields no jobs cannot reach --delete-old, which would remove every
# job JJB manages on the server.
job_count=$(generate "$work/generated")
if [ "$job_count" -eq 0 ] && [ "$INPUT_DELETE_OLD" = true ]; then
    echo "::error::Refusing to update with delete_old: the tree" \
        "generates no jobs, so every managed job would be deleted" >&2
    exit 1
fi

args=(--conf "$ini" update --workers "$INPUT_WORKERS")
if [ "$INPUT_DELETE_OLD" = true ]; then
    args+=(--delete-old)
fi
"$jjb" "${args[@]}" "$jjb_path"

printf 'job_count=%s\n' "$job_count" >> "$GITHUB_OUTPUT"
printf 'output_dir=\n' >> "$GITHUB_OUTPUT"
echo "Updated Jenkins with $job_count job(s) ✅"
