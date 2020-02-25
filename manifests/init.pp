# This module manages the configuration of [TLog](https://github.com/Scribery/tlog)
#
# @param package_name
#   The name of the tlog package
#
# @param package_ensure
#   What should be passed to the `ensure` parameter for all package resources
#
# @param manage_rsyslog
#   If true, manage logging configuration for tlog
#
# @author https://github.com/simp/pupmod-simp-tlog/graphs/contributors
#
class tlog (
  String[1] $package_name   = 'tlog',
  String[1] $package_ensure = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' }),
  Boolean   $manage_rsyslog = simplib::lookup('simp_options::syslog', { 'default_value' => false })
) {
  simplib::assert_metadata($module_name)

  include 'tlog::install'

  if $manage_rsyslog {
    include 'tlog::config::rsyslog'
  }
}
