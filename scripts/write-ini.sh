#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Write a jenkins_jobs.ini for Jenkins Job Builder.
#
# Usage: write-ini.sh <path>
#
# Takes the Jenkins URL, user and password from INPUT_JENKINS_URL,
# INPUT_JENKINS_USER and INPUT_JENKINS_PASSWORD, and writes them only
# when INPUT_MODE is 'update'. validate.sh has already rejected values
# that cannot survive the round trip.
#
# JJB reads the file with configparser.ConfigParser, whose default
# interpolation treats '%' as special, so each '%' is written as '%%'.
# Values are written with printf '%s', never through a heredoc or eval,
# so the shell expands nothing in them.

set -euo pipefail

ini=${1:?usage: write-ini.sh <path>}

umask 077
{
    printf '%s\n' \
        '[job_builder]' \
        'ignore_cache=True' \
        'keep_descriptions=False' \
        'include_path=.' \
        'recursive=True' \
        '' \
        '[jenkins]' \
        'query_plugins_info=False'
    if [ "${INPUT_MODE-}" = update ]; then
        printf 'url=%s\n' "${INPUT_JENKINS_URL//%/%%}"
        printf 'user=%s\n' "${INPUT_JENKINS_USER//%/%%}"
        printf 'password=%s\n' "${INPUT_JENKINS_PASSWORD//%/%%}"
    fi
} > "$ini"
chmod 0600 "$ini"
