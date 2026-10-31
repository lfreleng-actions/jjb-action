#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Validate the action inputs before anything runs.
#
# Reads the inputs from INPUT_* environment variables and fails closed
# on the first invalid one. Messages name the input but never print its
# value. Run from the directory
# path_prefix is relative to, normally GITHUB_WORKSPACE.

set -euo pipefail

fail() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

# Every character Python's str.isspace() accepts, which ConfigParser
# strips from a value. They are spelt as UTF-8 bytes because bash's
# [[:space:]] follows the locale and misses some, such as U+00A0.
whitespace=(
    ' ' $'\t' $'\n' $'\v' $'\f' $'\r' $'\x1c' $'\x1d' $'\x1e' $'\x1f'
    $'\xc2\x85' $'\xc2\xa0' $'\xe1\x9a\x80'
    $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83'
    $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87'
    $'\xe2\x80\x88' $'\xe2\x80\x89' $'\xe2\x80\x8a'
    $'\xe2\x80\xa8' $'\xe2\x80\xa9' $'\xe2\x80\xaf' $'\xe2\x81\x9f'
    $'\xe3\x80\x80'
)

# Exit 0 if $1 contains any whitespace character.
has_whitespace() {
    local ws
    for ws in "${whitespace[@]}"; do
        [[ $1 == *"$ws"* ]] && return 0
    done
    return 1
}

# A path input must be relative, with no '..' segment, no leading '-'
# (which a command could read as an option), and no whitespace or
# control characters.
check_path() {
    local name=$1 value=$2
    [ -n "$value" ] || fail "Input '$name' must not be empty"
    case $value in
        /*) fail "Input '$name' must be a relative path" ;;
        -*) fail "Input '$name' must not start with '-'" ;;
    esac
    if [[ $value =~ [[:space:][:cntrl:]] ]] || has_whitespace "$value"; then
        fail "Input '$name' must not contain whitespace or control characters"
    fi
    case /$value/ in
        */../*) fail "Input '$name' must not contain a '..' segment" ;;
    esac
}

mode=${INPUT_MODE-}
path_prefix=${INPUT_PATH_PREFIX-}
jjb_path=${INPUT_JJB_PATH-}

case $mode in
    test) ;;
    *) fail "Input 'mode' must be 'test'" ;;
esac

check_path path_prefix "$path_prefix"
check_path jjb_path "$jjb_path"

[ -d "$path_prefix" ] || fail "Input 'path_prefix' is not a directory"
[ -d "$path_prefix/$jjb_path" ] ||
    fail "Input 'jjb_path' is not a directory under path_prefix"

echo "Inputs are valid ✅"
