# This class is called from tlog for install.
#
# @api private
#
class tlog::install {
  assert_private()

  package { $::tlog::package_name:
    ensure => $::tlog::package_ensure
  }
}
