# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this module does

`simp-tlog` is a SIMP Puppet module that manages
[tlog](https://github.com/Scribery/tlog), a tool that **records terminal/shell
sessions for audit**. tlog sits between the user and the login shell,
capturing everything the recorded session sees (and optionally types) and
shipping it to a configured sink — the systemd journal, syslog, or a file.

The module does three things:

1. **Installs the tlog package** (`tlog::install`, which manages the `tlog`
   package that provides the `tlog-rec-session` binary).
2. **Configures the recording session** (`tlog::rec_session`) by writing
   `/etc/tlog/tlog-rec-session.conf` and installing `/etc/profile.d` shell
   hooks that transparently re-exec matching users' login/interactive shells
   under `tlog-rec-session` so their sessions are recorded.
3. **Optionally wires the recordings into local logging**
   (`tlog::config::rsyslog`) — an rsyslog rule to route the session records to
   a log file, plus optional logrotate rotation of that file.

The main `tlog` class only installs the package and (conditionally) pulls in
rsyslog configuration; the shell-hook / session-configuration logic lives in
`tlog::rec_session`, which is deliberately decoupled because upstream tlog
moves fast (`manifests/rec_session.pp`).

### Business logic

Four classes, one custom data type, no defines.

- **`tlog` (`manifests/init.pp`)** — public entry class. Consumers
  `include 'tlog'`. Parameters (`init.pp`):
  - `$package_name` (`String[1]`, default `'tlog'`).
  - `$package_ensure` (`String[1]`) — defaults to
    `simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })`
    (`init.pp`).
  - `$manage_rsyslog` (`Boolean`) — defaults to
    `simplib::lookup('simp_options::syslog', { 'default_value' => false })`
    (`init.pp`). When true, `include 'tlog::config::rsyslog'`
    (`init.pp`).

  It always `include`s `tlog::install` (`init.pp`) and asserts module
  metadata (`init.pp`).

- **`tlog::install` (`manifests/install.pp`)** — `@api private`, calls
  `assert_private()` (`install.pp`); managed only via `include 'tlog'`.
  Declares `package { $tlog::package_name: ensure => $tlog::package_ensure }`
  (`install.pp`).

- **`tlog::rec_session` (`manifests/rec_session.pp`)** — `@api public`.
  This is **not** pulled in by the `tlog` class; a site includes it explicitly
  to turn on session recording. It `include`s `tlog` (`rec_session.pp`).
  Parameters (`rec_session.pp`):
  - `$options` (`Tlog::RecSessionConf`, **no default**) — required; the
    structured tlog-rec-session config (see the type below). Deep-merged
    through Hiera; default content comes from `data/common.yaml` and the
    `data/journald/` tree.
  - `$custom_options` (`Hash`, default `{}`) — **unvalidated** escape hatch,
    converted to JSON and merged with preference into `$options`
    (`rec_session.pp`).
  - `$shell_hook` (`Boolean`, default `true`) — install the `/etc/profile.d`
    hooks that auto-record.
  - `$shell_hook_users` (`Array[String[1]]`, default `['root']`) — written to
    `$shell_hook_users_file`, one per line.
  - `$shell_hook_users_file` (`Stdlib::Absolutepath`, default
    `/etc/security/tlog.users`).
  - `$shell_hook_cmd` (`Stdlib::Absolutepath`, default
    `/usr/bin/tlog-rec-session`).

  Resources:
  - `file { '/etc/tlog/tlog-rec-session.conf' }` — JSON of
    `deep_merge($options, $custom_options)` (`rec_session.pp`).
  - If `$options['writer'] == 'file'`, `ensure_resource`s the output file at
    `$options['file']['path']` owned `tlog:tlog` mode `0640`
    (`rec_session.pp`).
  - `file { '/etc/profile.d/00-simp-tlog.sh' }` and `{ '...00-simp-tlog.csh' }`
    — rendered from `templates/etc/profile.d/tlog.sh.epp` / `tlog.csh.epp` via
    `epp()` with `users_file` + `app_path` (`rec_session.pp`). **The
    template files are named `tlog.sh.epp` / `tlog.csh.epp`; the installed
    files are `00-simp-tlog.sh` / `.csh`** — the `00-` prefix makes them run
    first in `/etc/profile.d`.
  - `file { $shell_hook_users_file }` — the users list (`rec_session.pp`).
  - When `$shell_hook` is false, the three hook files + users file are set to
    `ensure => 'absent'` via the `$_hook_file_ensure` selector
    (`rec_session.pp`).
  - Ordering: `Class['tlog::install']` is applied before the conf file always,
    and before the hook files only when `$shell_hook` (`rec_session.pp`).

- **`tlog::config::rsyslog` (`manifests/config/rsyslog.pp`)** — routes
  session records into local logging. Parameters (`rsyslog.pp`):
  - `$logrotate_options` (`Hash`, **no default**) — supplied from
    `data/common.yaml`; merged into the logrotate rule.
  - `$match_rule` (`String[1]`) — rsyslog selector matching the
    `tlog-rec-session` / `tlog` program names (`rsyslog.pp`).
  - `$log_file` (`Stdlib::Absolutepath`, default `/var/log/tlog.log`).
  - `$logrotate_create` (`Pattern['\d{4} .+ .+']`, default `'0640 tlog tlog'`).
  - `$stop_processing` (`Boolean`, default `true`).
  - `$logrotate` (`Boolean`) — defaults to
    `simplib::lookup('simp_options::logrotate', { 'default_value' => false })`
    (`rsyslog.pp`).

  It asserts `simp/rsyslog` (`rsyslog.pp`), `include`s `rsyslog`, declares
  `rsyslog::rule::local { 'XX_tlog' }` (named `XX_` so it sorts before the
  local-filesystem defaults, `rsyslog.pp`). When `$logrotate`, it
  asserts `simp/logrotate` (`rsyslog.pp`), `include`s `logrotate`, and
  declares `logrotate::rule { 'tlog' }` (`rsyslog.pp`).

- **`Tlog::RecSessionConf` (`types/recsessionconf.pp`)** — the struct type
  validating `$tlog::rec_session::options`. All keys optional: `shell`,
  `notice`, `writer` (`Enum['journal','syslog','file']`), `latency`, `payload`,
  and nested structs `log` (input/output/window booleans), `limit`
  (rate/burst/action), `file` (required `path`), `syslog`
  (facility/priority using `Simplib::Syslog::*` types), and `journal`
  (priority/augment).

## The `simp_options` / `simplib::lookup` seam

The module's SIMP feature-toggle seam. Each call routes a SIMP-wide option
through `simplib::lookup` with an explicit default:

| Location | Key | `default_value` | Effect |
|----------|-----|-----------------|--------|
| `init.pp` | `simp_options::package_ensure` | `'installed'` | package ensure |
| `init.pp` | `simp_options::syslog` | `false` | drives `$manage_rsyslog` → pulls in `tlog::config::rsyslog` |
| `manifests/config/rsyslog.pp` | `simp_options::logrotate` | `false` | drives `$logrotate` → logrotate rule + `simp/logrotate` assertion |

Keep routing SIMP toggles through `simplib::lookup('simp_options::*', {
'default_value' => ... })` with an explicit default rather than assuming
`simp_options` is included.

## Gotchas / non-obvious details

- **The `tlog` class does not record anything by itself.** It only installs the
  package (and, if `simp_options::syslog`, configures rsyslog). Session
  recording requires explicitly including `tlog::rec_session`
  (`init.pp`, `rec_session.pp`).
- **The shell hook silently re-execs matching users into `tlog-rec-session`.**
  The `/etc/profile.d/00-simp-tlog.sh` / `.csh` scripts check whether the
  current user (or a `%group`) is listed in `/etc/security/tlog.users` and, if
  so and a TTY is present, `exec` the shell under `tlog-rec-session`
  (`templates/etc/profile.d/tlog.sh.epp`). By default only `root` is recorded
  (`rec_session.pp`). Keyboard **input capture is off by default** —
  `data/common.yaml` sets `log.input: false` to avoid capturing typed secrets.
- **Template vs. installed filename mismatch.** Templates are
  `tlog.sh.epp` / `tlog.csh.epp`; installed files are `00-simp-tlog.sh` /
  `.csh` (`rec_session.pp`). Don't assume the on-disk profile.d name
  matches the template name.
- **`$custom_options` is unvalidated.** Anything in it bypasses the
  `Tlog::RecSessionConf` type and is merged into the config JSON with
  precedence (`rec_session.pp`). The tlog config file is not "real"
  JSON, so Augeas/Ruby can't safely edit it ad hoc (`rec_session.pp`).
- **The default `writer` is chosen by the `systemd` fact.** `data/journald/`
  keys off `is_%{facts.systemd}` (`hiera.yaml`): systemd present →
  `writer: journal` (`data/journald/is_true.yaml`); otherwise `writer: syslog`
  (`is_false.yaml` and the empty-fact `is_.yaml`).
- **Optional dependencies are asserted only when the feature is on.**
  `simp/rsyslog` and `simp/logrotate` are declared as *optional* in
  `metadata.json` and guarded at runtime by
  `simplib::assert_optional_dependency` — `simp/rsyslog` at
  `manifests/config/rsyslog.pp` (whenever rsyslog config runs) and `simp/logrotate` at
  `manifests/config/rsyslog.pp` (only when `$logrotate` is true). If the feature is
  off, the module works without those modules installed.
- **`tlog::rec_session` requires `$options`.** It has no default and is
  typed `Tlog::RecSessionConf`; the value comes from Hiera
  (`data/common.yaml` + `data/journald/`), so tests/consumers must supply it.
- **CI does not run acceptance** — see the CI subsection below.

## Dependencies

Module dependencies (from `metadata.json`):

- `simp/simplib` `>= 4.9.0 < 5.0.0` (provides `simplib::lookup`,
  `simplib::assert_metadata`, `simplib::assert_optional_dependency`, and the
  `Simplib::Syslog::*` types used by `Tlog::RecSessionConf`).
- `puppetlabs/stdlib` `>= 8.0.0 < 10.0.0` (provides `deep_merge`, `to_json`,
  `ensure_resource`, `Stdlib::Absolutepath`).

Optional dependencies (from `metadata.json` `simp.optional_dependencies`) —
required **only** when the corresponding feature is enabled, and asserted at
runtime with `simplib::assert_optional_dependency`:

- `simp/rsyslog` `>= 7.6.0 < 9.0.0` — needed when rsyslog config runs
  (asserted `manifests/config/rsyslog.pp`).
- `simp/logrotate` `>= 6.5.0 < 7.0.0` — needed when `$logrotate` is true
  (asserted `manifests/config/rsyslog.pp`).

Runtime requirement (from `metadata.json` `requirements`):
`puppet >= 7.0.0 < 9.0.0`. This is the older SIMP baseline — the module is
**not yet migrated to OpenVox**. When `metadata.json` switches `puppet` to
`openvox`, update this line and the Gemfile's default range to match.

Supported OS matrix (from `metadata.json`): CentOS 7/8/9; RedHat 7/8/9;
OracleLinux 7/8/9; Rocky 8/9; AlmaLinux 8/9.

## Repository layout

- `manifests/init.pp` — the `tlog` class (install + conditional rsyslog).
- `manifests/install.pp` — `tlog::install` (private; the package resource).
- `manifests/rec_session.pp` — `tlog::rec_session` (session config + shell
  hooks).
- `manifests/config/rsyslog.pp` — `tlog::config::rsyslog` (rsyslog rule +
  optional logrotate).
- `types/recsessionconf.pp` — the `Tlog::RecSessionConf` struct type. **No
  `lib/`** — the module ships no Ruby functions/facts/types/providers.
- `templates/etc/profile.d/tlog.sh.epp`, `tlog.csh.epp` — `.epp` (embedded
  Puppet) templates for the sh/csh shell hooks.
- `data/common.yaml` — default `rec_session::options` and
  `config::rsyslog::logrotate_options`, with deep-merge `lookup_options`.
- `data/journald/is_%{facts.systemd}.yaml` — per-systemd default `writer`
  (`is_true` → journal; `is_false`/`is_` → syslog).
- `hiera.yaml` — v5 module data hierarchy: `journald` (systemd fact) → `common`.
- `metadata.json` — deps, optional deps, OS matrix, Puppet requirement.
- `spec/classes/` — rspec-puppet unit tests.
- `spec/acceptance/suites/default/` — beaker suites (`00_default_spec.rb`,
  `10_tlog_rec_session_spec.rb`, `20_hidepid_spec.rb`) plus `include/` and
  `lib/` helpers; nodesets in `spec/acceptance/nodesets/`
  (`centos-combined-x64.yml`, `default.yml`, `oel-combined-x64.yml`).
- `REFERENCE.md` — generated Puppet Strings reference.

### CI (`.github/workflows/pr_tests.yml`)

The PR workflow runs **six jobs only**: `puppet-syntax`, `puppet-style`,
`ruby-style`, `file-checks`, `releng-checks`, and `spec-tests`.

- **There is no acceptance job.** The beaker suites and nodesets on disk are
  **not wired into CI** — nothing runs `rake beaker:suites`. Acceptance must be
  run manually/locally.
- This is an **older workflow style**: a global `env: PUPPET_VERSION: '~> 7'`
  (`pr_tests.yml`) and Ruby pinned to 2.7.8 for the check jobs.
- `spec-tests` runs a Puppet 7.x (Ruby 2.7) + Puppet 8.x (Ruby 3.2) matrix
  (`pr_tests.yml`) and `needs: [puppet-syntax]`.
- `ruby-style` is `continue-on-error: true` (`pr_tests.yml`).

## Common commands

```sh
# Install dependencies
bundle install

# Run all unit tests
bundle exec rake spec

# Puppet syntax + lint (mirrors the puppet-syntax / puppet-style CI jobs)
bundle exec rake syntax
bundle exec rake lint
bundle exec rake metadata_lint

# Ruby lint
bundle exec rake rubocop

# Test-build the module (mirrors the releng-checks job)
bundle exec pdk build --force

# Regenerate REFERENCE.md from puppet-strings docstrings
puppet strings generate --format markdown --out REFERENCE.md

# Run a beaker acceptance suite MANUALLY (CI does not do this)
bundle exec rake beaker:suites[default]
```

Relevant gem pins (from `Gemfile`): `rubocop ~> 1.88.0` (`Gemfile`),
`puppetlabs_spec_helper ~> 8.0.0` (`Gemfile`), `simp-rake-helpers
~> 5.24.0` (`Gemfile`), `simp-beaker-helpers ~> 2.0.0` (`Gemfile`). The
Puppet gem is pulled **only** via `gem 'puppet', puppet_version` (`Gemfile`),
where `puppet_version` defaults to `['>= 7', '< 9']` (`Gemfile`). Unit specs
require `spec/spec_helper.rb` (the standard puppetsync helper, `require`).

## Conventions

- Preserve the `@summary` / `@param` puppet-strings docstrings on the classes
  and the `Tlog::RecSessionConf` type — they drive `REFERENCE.md`. Regenerate
  `REFERENCE.md` after changing docs, parameters, or the type.
- Keep default session/logrotate options in `data/*.yaml` (deep-merged via
  `lookup_options`), not hard-coded in the manifests.
- Route SIMP feature toggles through
  `simplib::lookup('simp_options::*', { 'default_value' => ... })` with an
  explicit default rather than assuming `simp_options` is included.
- Guard optional integrations (`rsyslog`, `logrotate`) with
  `simplib::assert_optional_dependency` before `include`ing them — don't add
  them as hard dependencies, and don't `include` an optional module without
  asserting it first, as `manifests/config/rsyslog.pp` does.
- Validate structured config through the `Tlog::RecSessionConf` type; reserve
  `$custom_options` for genuinely arbitrary/unvalidated settings.
- `Gemfile`, `spec/spec_helper.rb`, and `.github/workflows/pr_tests.yml` carry
  a **puppetsync** notice — they are baseline-managed and the next sync
  overwrites local edits. Push changes to those files upstream to the baseline,
  not here.
- Match the existing 2-space Puppet indentation and aligned-arrow parameter
  style used throughout `manifests/`.
