# Configure `tlog-rec-session`
#
# This is pulled out from the main `tlog` class because of the rapidly moving
# nature of the project. Having this decoupled will allow us to refactor as
# necessary as the software progresses.
#
# @api public
#
# @param options
#   Configuration options for tlog-rec-session
#
#   * Will be deep merged through Hiera by default
#   * Unfortunately, the file is not "real" JSON and so Augeas lenses and/or
#     Ruby won't work to do ad-hoc configuration until after the file is managed.
#   * This set covers the known options in known formats. Use `$custom_options`
#     for arbitrary settings.
#   * Note: If the `writer` option is not set, a sane default for the target
#     platform will be selected.
#
#   @see data/common.yaml
#   @see types/recsession.pp
#
# @param custom_options
#   An **unvalidated** `Hash` of options that will be converted to JSON and
#   merged, with preference, into `$options`
#
# @param shell_hook
#   Add hooks into /etc/profile.d that will automatically record sessions for
#   interactive and/or login shells
#
# @param shell_hook_users
#   The list of users that you want to automatically record that will be stored
#   in `$shell_hook_users_file`
#
# @param shell_hook_users_file
#   The path to the file containing the list of users and/or groups that you
#   want to automatically record
#
#   * Users should be specified as `Strings`
#   * Groups should be prefaces with a `%`
#
# @param shell_hook_cmd
#
#   The path to `tlog-rec-session`
#
# @author https://github.com/simp/pupmod-simp-tlog/graphs/contributors
#
class tlog::rec_session (
  Tlog::RecSessionConf $options,
  Hash                 $custom_options        = {},
  Boolean              $shell_hook            = true,
  Array[String[1]]     $shell_hook_users      = [ 'root' ],
  Stdlib::Absolutepath $shell_hook_users_file = '/etc/security/tlog.users',
  Stdlib::Absolutepath $shell_hook_cmd        = '/usr/bin/tlog-rec-session'
) {
  simplib::assert_metadata($module_name)

  include 'tlog'

  $_file_defaults = {
    owner   => 'root',
    group   => 'root',
    mode    => '0644'
  }

  # Ensure the file resource exists if we are using a file writer
  if $options['writer'] == 'file' {
    $_tlog_output_file_opts = {
      ensure => 'file',
      owner  => 'tlog',
      group  => 'tlog',
      mode   => '0640',
    }
    ensure_resource('file', $options['file']['path'], $_tlog_output_file_opts)
  }

  file { '/etc/tlog/tlog-rec-session.conf':
    ensure  => 'file',
    content => sprintf("%s\n", to_json(deep_merge($options, $custom_options))),
    *       => $_file_defaults
  }

  $_hook_file_ensure = $shell_hook ? {
    true    => 'file',
    default => 'absent'
  }

  file { '/etc/profile.d/00-simp-tlog.sh':
    ensure  => $_hook_file_ensure,
    content => epp("${module_name}/etc/profile.d/tlog.sh.epp",
      {
        'users_file' => $shell_hook_users_file,
        'app_path'   => $shell_hook_cmd
      }
    ),
    *       => $_file_defaults
  }

  file { '/etc/profile.d/00-simp-tlog.csh':
    ensure  => $_hook_file_ensure,
    content => epp("${module_name}/etc/profile.d/tlog.csh.epp",
      {
        'users_file' => $shell_hook_users_file,
        'app_path'   => $shell_hook_cmd
      }
    ),
    *       => $_file_defaults
  }

  file { $shell_hook_users_file:
    ensure  => $_hook_file_ensure,
    content => sprintf("%s\n", join($shell_hook_users, "\n")),
    *       => $_file_defaults
  }

  Class['tlog::install'] -> File['/etc/tlog/tlog-rec-session.conf']

  if $shell_hook {
    Class['tlog::install'] -> File['/etc/profile.d/00-simp-tlog.sh']
    Class['tlog::install'] -> File['/etc/profile.d/00-simp-tlog.csh']
    Class['tlog::install'] -> File[$shell_hook_users_file]
  }
}
