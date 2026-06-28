require 'spec_helper_acceptance'
require 'net/ssh'

test_name 'tlog::rec_session with hidepid'

describe 'tlog::rec_session' do
  hosts.each do |host|
    context "on #{host}" do
      context 'with hidepid enabled' do
        it 'remounts /proc' do
          # Remounting /proc with hidepid is a kernel-level mount operation. It
          # works on full VMs (vagrant) but is blocked under rootless-podman +
          # seccomp in CI (the mount/remount of /proc is not permitted). Probe by
          # attempting the remount; if the runtime rejects it, skip the hidepid
          # scenario rather than failing red. The non-hidepid recording coverage
          # in 10_tlog_rec_session_spec already exercises tlog's core on
          # containers; hidepid stays live on vagrant.
          result = on(host, 'mount -o remount,hidepid=2,rw,nosuid,nodev,noexec,relatime /proc',
                      accept_all_exit_codes: true)
          # Newer kernels render `hidepid=2` as `hidepid=invisible` in findmnt;
          # accept either so the hidepid coverage stays live where the remount
          # genuinely takes effect.
          mounted_hidepid = on(host, 'findmnt -n /proc', accept_all_exit_codes: true).output =~ %r{hidepid=(2|invisible)}
          unless result.exit_code.zero? && mounted_hidepid
            skip('cannot remount /proc with hidepid under this container runtime ' \
                 '(kernel-level mount blocked by rootless-podman/seccomp); ' \
                 'hidepid scenario is validated on vagrant/bare-metal')
          end
        end

        require_relative('include/remote_user_login_tests')

        include_context 'remote user logins', host
      end
    end
  end
end
