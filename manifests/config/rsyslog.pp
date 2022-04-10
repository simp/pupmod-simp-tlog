# Manage local syslog hooks for tlog
#
# @param logrotate_options
#   Options to pass to the `logrotate::rule` defined type
#
#   * Will be deep merged through Hiera by default
#   * The `log_files` option will not be honored if passed
#
#   @see `data/common.yaml`
#
# @param match_rule
#   The rule that should be used for matching TLOG rules
#
#   * The default is set to match rules on the widest selection of systems
#     possible.
#
# @param log_file
#   The log file in which to save the `tlog` logs
#
# @param logrotate_create
#   The create options to specify in the logrotate rule
#
# @param stop_processing
#   Cease processing syslog rules after processing this rule
#
# @param logrotate
#   Enable log rotation for `$log_file`
#
class tlog::config::rsyslog (
  Hash                   $logrotate_options,
  String[1]              $match_rule       = '$programname == \'tlog-rec-session\' or $programname == \'-tlog-rec-session\' or $programname == \'tlog\'',
  Stdlib::Absolutepath   $log_file         = '/var/log/tlog.log',
  Pattern['\d{4} .+ .+'] $logrotate_create = '0640 tlog tlog',
  Boolean                $stop_processing  = true,
  Boolean                $logrotate        = simplib::lookup('simp_options::logrotate', { 'default_value' => false })
) {
  simplib::assert_optional_dependency($module_name, 'simp/rsyslog')

  include 'rsyslog'

  # named 'XX_tlog' so that it appears before the local filesystem defaults
  rsyslog::rule::local { 'XX_tlog':
    rule            => $match_rule,
    target_log_file => $log_file,
    stop_processing => $stop_processing
  }

  if $logrotate {
    simplib::assert_optional_dependency($module_name, 'simp/logrotate')

    include 'logrotate'

    $_rule_opts = $logrotate_options + {'log_files' => [ $log_file ]} + {'create' => $logrotate_create}

    logrotate::rule { 'tlog': * => $_rule_opts }
  }
}
