require 'spec_helper_acceptance'
require 'net/ssh'

test_name 'tlog::rec_session with hidepid'

describe 'tlog::rec_session' do
  hosts.each do |host|
    ssh_info = host.connection.instance_variable_get('@ssh').options

    context "on #{host}" do
      context 'with hidepid enabled' do
        it 'should remount /proc' do
          on(host, 'mount -o remount,hidepid=2,rw,nosuid,nodev,noexec,relatime /proc')
        end

        require_relative('include/remote_user_login_tests')

        include_context 'remote user logins', host, ssh_info
      end
    end
  end
end
