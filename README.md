

[![License](https://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/73/badge)](https://bestpractices.coreinfrastructure.org/projects/73)
[![Puppet Forge](https://img.shields.io/puppetforge/v/simp/tlog.svg)](https://forge.puppetlabs.com/simp/tlog)
[![Puppet Forge Downloads](https://img.shields.io/puppetforge/dt/simp/tlog.svg)](https://forge.puppetlabs.com/simp/tlog)
[![Build Status](https://travis-ci.org/simp/pupmod-simp-tlog.svg)](https://travis-ci.org/simp/pupmod-simp-tlog)

#### Table of Contents

## Description

This module manages the installation and configuration of
[tlog](http://scribery.github.io/tlog/) for active terminal session recording.

By default, the logs will be recorded to `journald` with systems running
`systemd` and `syslog` otherwise.

### This is a SIMP module

This module is a component of the [System Integrity Management Platform](https://simp-project.com),
a compliance-management framework built on Puppet.

If you find any issues, they may be submitted to our
[bug tracker](https://simp-project.atlassian.net/).

## Usage

You can simply include the `tlog` class to have the software installed.

To enable automatic session recording, include the `tlog::rec_session` class
and add the users and/or groups that you want to monitor to the
`tlog::rec_session::shell_hook_users` Array. Note: Groups should be prefixed
with a percent sign (`%`) and it currently only works with the users primary
group.

When this is enabled, it will automatically hook into login and interactive
shells based on scripts placed into `/etc/profile.d`.

### Example: Auditing the 'root' user and 'administrators' group

```yaml
---
tlog::rec_session::shell_hook_users:
  - 'root'
  - '%administrators'
```

NOTE: If you want to be 100% certain that all sessions are logged, you should
not rely on this hook but should, instead, set `/usr/bin/tlog-rec-session` as
the user's primary shell. This is not feasible in many situations so these
hooks have been provided for the 90% case.

## Limitations

The `tlog` project is still evolving so there may be breaking changes that
occur in the future. We highly encourage all users to file feature requests and
bug reports with the [upstream project](https://github.com/Scribery/tlog).

## Development

Please read our [Contribution Guide](http://simp-doc.readthedocs.io/en/stable/contributors_guide/index.html).

### Acceptance tests

This module includes [Beaker](https://github.com/puppetlabs/beaker) acceptance
tests using the SIMP [Beaker Helpers](https://github.com/simp/rubygem-simp-beaker-helpers).
By default the tests use [Vagrant](https://www.vagrantup.com/) with
[VirtualBox](https://www.virtualbox.org) as a back-end; Vagrant and VirtualBox
must both be installed to run these tests without modification. To execute the
tests run the following:

NOTE: You will need to make sure that the `nodesets` can install the `tlog`
packages from a repository (or install them via `beaker`) for the tests to run
successfully.

```shell
bundle install
bundle exec rake beaker:suites
```

Please refer to the [SIMP Beaker Helpers documentation](https://github.com/simp/rubygem-simp-beaker-helpers/blob/master/README.md)
for more information.
