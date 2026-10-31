#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Validate the action inputs before anything runs.
#
# Reads the inputs from INPUT_* environment variables and fails closed
# on the first invalid one. Messages name the input but never print its
# value, since some of them are credentials. Run from the directory
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

# ConfigParser strips surrounding whitespace and reads a new line as a
# continuation, so such a value would not reach Jenkins unchanged.
check_ini_value() {
    local name=$1 value=$2 ws
    [ -n "$value" ] || fail "Input '$name' is required in update mode"
    if [[ $value =~ [[:cntrl:]] ]]; then
        fail "Input '$name' must not contain control characters"
    fi
    for ws in "${whitespace[@]}"; do
        if [[ $value == "$ws"* || $value == *"$ws" ]]; then
            fail "Input '$name' must not start or end with whitespace"
        fi
    done
}

# The Jenkins URL must be https:// with a host name, which a dotted
# IPv4 address also matches, then an optional port from 1 to 65535.
# A bracketed IP literal is refused: callers run harden-runner in
# block mode, whose allow-lists name hosts. User info is refused; the
# credentials have inputs of their own.
check_url() {
    local value=$1 rest authority tail host='' port=''
    local message="Input 'jenkins_url' must be an https:// URL with a host"
    local label='[A-Za-z0-9_]([A-Za-z0-9_-]*[A-Za-z0-9_])?'
    local name_re="^$label([.]$label)*[.]?\$"
    local split_re='^([^:]*)(.*)$'
    [[ $value == https://* ]] || fail "$message"
    rest=${value#https://}
    authority=${rest%%[/?#]*}
    tail=${rest#"$authority"}
    if [[ $authority == *@* ]]; then
        fail "Input 'jenkins_url' must not carry user info"
    fi
    if [[ $authority == *'['* ]]; then
        fail "Input 'jenkins_url' must name its host by DNS name, not an IP literal"
    fi
    if [[ $authority =~ $split_re ]]; then
        host=${BASH_REMATCH[1]}
        port=${BASH_REMATCH[2]}
    fi
    [[ $host =~ $name_re ]] || fail "$message"
    if [ -n "$port" ]; then
        if ! [[ $port =~ ^:[1-9][0-9]{0,4}$ ]] || [ "${port#:}" -gt 65535 ]; then
            fail "Input 'jenkins_url' has an invalid port"
        fi
    fi
    if [[ $tail =~ [[:space:]] ]] || has_whitespace "$tail"; then
        fail "Input 'jenkins_url' must not contain whitespace"
    fi
}

mode=${INPUT_MODE-}
path_prefix=${INPUT_PATH_PREFIX-}
jjb_path=${INPUT_JJB_PATH-}
jenkins_url=${INPUT_JENKINS_URL-}
jenkins_user=${INPUT_JENKINS_USER-}
jenkins_password=${INPUT_JENKINS_PASSWORD-}
delete_old=${INPUT_DELETE_OLD-}
workers=${INPUT_WORKERS-}

case $mode in
    test | update) ;;
    *) fail "Input 'mode' must be 'test' or 'update'" ;;
esac

check_path path_prefix "$path_prefix"
check_path jjb_path "$jjb_path"

case $delete_old in
    true | false) ;;
    *) fail "Input 'delete_old' must be 'true' or 'false'" ;;
esac

if ! [[ $workers =~ ^(0|[1-9][0-9]?)$ ]] || [ "$workers" -gt 64 ]; then
    fail "Input 'workers' must be an integer from 0 to 64"
fi

if [ "$mode" = update ]; then
    check_ini_value jenkins_url "$jenkins_url"
    check_ini_value jenkins_user "$jenkins_user"
    check_ini_value jenkins_password "$jenkins_password"
    check_url "$jenkins_url"
elif [ -n "$jenkins_url$jenkins_user$jenkins_password" ]; then
    echo "::warning::The jenkins_* inputs are ignored in test mode"
fi

[ -d "$path_prefix" ] || fail "Input 'path_prefix' is not a directory"
[ -d "$path_prefix/$jjb_path" ] ||
    fail "Input 'jjb_path' is not a directory under path_prefix"

echo "Inputs are valid ✅"
