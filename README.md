<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# 🏗️ Jenkins Job Builder Action

<!-- prettier-ignore-start -->
<!-- markdownlint-disable-next-line MD013 -->
[![Linux Foundation](https://img.shields.io/badge/Linux-Foundation-blue)](https://linuxfoundation.org/) [![Source Code](https://img.shields.io/badge/GitHub-100000?logo=github&logoColor=white&color=blue)](https://github.com/lfreleng-actions/jjb-action) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![pre-commit.ci status badge]][pre-commit.ci results page] [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/lfreleng-actions/jjb-action/badge)](https://scorecard.dev/viewer/?uri=github.com/lfreleng-actions/jjb-action)
<!-- prettier-ignore-end -->

Runs [Jenkins Job Builder](https://jenkins-job-builder.readthedocs.io/)
(JJB) against a ci-management repository, with a pinned JJB and no
credentials in the workspace.

- `mode: test` generates the job XML for a change under review. It needs
  no credentials and no Jenkins.
- `mode: update` pushes the jobs to Jenkins after a merge.

## Usage Example

<!-- markdownlint-disable MD046 -->

Verify an unmerged change:

```yaml
steps:
  - name: "Checkout repository"
    uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      submodules: true
      persist-credentials: false

  - name: "Test the Jenkins jobs"
    id: jjb
    uses: lfreleng-actions/jjb-action@main
    with:
      mode: test

  - name: "Report the job count"
    shell: bash
    env:
      JOB_COUNT: ${{ steps.jjb.outputs.job_count }}
    run: echo "JJB generated $JOB_COUNT jobs"
```

Update Jenkins after a merge:

```yaml
steps:
  - name: "Checkout repository"
    uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      submodules: true
      persist-credentials: false

  - name: "Update the Jenkins jobs"
    uses: lfreleng-actions/jjb-action@main
    with:
      mode: update
      jenkins_url: "https://jenkins.example.org"
      jenkins_user: ${{ vars.JENKINS_USER }}
      jenkins_password: ${{ secrets.JENKINS_PASSWORD }}
```

<!-- markdownlint-enable MD046 -->

Pin the action to a commit SHA in real workflows. These two reusable
workflows in
[generic-workflows](https://github.com/lfreleng-actions/generic-workflows)
call it:

- `ci-management-verify.yaml` runs `mode: test` on an unmerged Gerrit
  change
  ([lfreleng-actions/generic-workflows#106](https://github.com/lfreleng-actions/generic-workflows/issues/106)).
- `ci-management-merge.yaml` runs `mode: update` after a merge
  ([lfreleng-actions/generic-workflows#107](https://github.com/lfreleng-actions/generic-workflows/issues/107)).

## Inputs

<!-- markdownlint-disable MD013 -->

| Name             | Required    | Default | Description                                                                        |
| ---------------- | ----------- | ------- | ---------------------------------------------------------------------------------- |
| mode             | False       | `test`  | `test` or `update`                                                                 |
| path_prefix      | False       | `.`     | Repository root; JJB runs from here, with `include_path=.`                         |
| jjb_path         | False       | `jjb`   | JJB tree, relative to `path_prefix`, processed recursively                         |
| jenkins_url      | Update mode |         | Jenkins URL; must use `https://` and name its host by DNS name                     |
| jenkins_user     | Update mode |         | Jenkins user                                                                       |
| jenkins_password | Update mode |         | Jenkins password or API token; pass it from a secret                               |
| delete_old       | False       | `true`  | Update mode: pass `--delete-old`, removing managed jobs the tree no longer defines |
| workers          | False       | `0`     | Update mode: `--workers`, an integer from 0 to 64; 0 means one per CPU             |

<!-- markdownlint-enable MD013 -->

The action checks every input before it runs anything, and fails without
printing the value it rejected. `path_prefix` and `jjb_path` must be
relative directories with no `..` segment, no leading `-`, and no
whitespace or control characters. The Jenkins URL, user and password may
not contain control characters or start or end with whitespace, Unicode
whitespace such as U+00A0 included, since the ini file could not carry
such a value unchanged. The URL must name its host by DNS name, takes
an optional port from 1 to 65535, and may not carry user info; the
host-name rule also admits a dotted IPv4 address. A bracketed IP
literal such as `https://[2001:db8::1]` fails: callers run
harden-runner in block mode, whose allow-lists name hosts. Test mode
ignores the `jenkins_*` inputs, with a warning.

## Outputs

<!-- markdownlint-disable MD013 -->

| Name       | Description                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------- |
| job_count  | Number of jobs the tree generates, as JJB counts them; views are not jobs                                |
| output_dir | Test mode: the generated XML under `RUNNER_TEMP`, one `<job>/config.xml` per job (`--config-xml` layout) |

<!-- markdownlint-enable MD013 -->

## Modes

### Test

Runs `jenkins-jobs --conf <ini> test --config-xml -o <output_dir>
<jjb_path>` from `path_prefix`. A tree JJB cannot expand fails the
step.

### Update

1. Generates the tree, as in test mode, into a private directory. A
   broken tree fails here, before the action contacts Jenkins.
2. When `delete_old` is `true` and the tree yields no jobs, the action
   refuses to continue. `--delete-old` would otherwise delete every job
   JJB manages on the server.
3. Runs `jenkins-jobs --conf <ini> update --workers <workers>
   [--delete-old] <jjb_path>`.

## Security Notes

- **No interpolation into scripts.** Inputs reach the shell through
  `env:`, never through `${{ }}` inside a `run:` block, so a value
  cannot inject a command.
- **The ini file.** The action writes `jenkins_jobs.ini` into a private
  directory under `RUNNER_TEMP`, with mode `0600`, never into the
  workspace, and removes it on every exit path. Values reach it through
  `printf '%s'`, so the shell expands nothing in them, and the action
  doubles each `%`, since JJB's `ConfigParser` would otherwise
  interpolate it. A test reads every value back through JJB itself. The
  action never prints a value, and holds the credentials in update mode
  alone.
- **The empty-tree refusal.** An update with `delete_old` and a tree
  that yields no jobs fails instead of wiping the server.
- **Pinned install.** JJB and every dependency come from a hash-locked
  `requirements.txt`, installed as wheels with `--require-hashes` into a
  virtualenv on a pinned Python, so pip fetches no build backend. The
  action upgrades nothing, pip included, and leaves the caller's `PATH`
  alone. Python runs the installer isolated (`-I`), so a `venv.py` or
  `pip.py` in the workspace cannot take its place.

## Implementation Details

Each release pins one JJB version, today 6.5.0. `requirements.in` names
it; `requirements.txt` is the lock compiled from it with
`pip-compile --allow-unsafe --generate-hashes --strip-extras
requirements.in` on Python 3.12, the version `action.yaml` installs.
Dependabot proposes updates to the lock.

JJB 6.5.0 imports `pkg_resources` without declaring `setuptools`, which
dropped `pkg_resources` in v81. The lock carries a
`setuptools` below v81; without it every `jenkins-jobs` command fails to
load (RELENG-5179).

The ini file sets `ignore_cache=True`, `keep_descriptions=False`,
`include_path=.` and `recursive=True` under `[job_builder]`, and
`query_plugins_info=False` under `[jenkins]`, plus `url`, `user` and
`password` in update mode.

With `recursive=True` JJB reads each directory under `jjb_path`. It
reads a symlinked directory, such as the `jjb/global-jjb` link
ci-management repositories point at their `global-jjb` submodule, but
does not descend into directories below the link.

[pre-commit.ci results page]: https://results.pre-commit.ci/latest/github/lfreleng-actions/jjb-action/main
[pre-commit.ci status badge]: https://results.pre-commit.ci/badge/github/lfreleng-actions/jjb-action/main.svg
