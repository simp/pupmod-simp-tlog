require 'spec_helper_acceptance'
require 'net/ssh'

test_name 'tlog::rec_session with hidepid'

describe 'tlog::rec_session' do
  hosts.each do |host|
    context "on #{host}" do
      context 'with hidepid enabled' do
        it 'remounts /proc' do
          on(host, 'mount -o remount,hidepid=2,rw,nosuid,nodev,noexec,relatime /proc')
        end

        require_relative('include/remote_user_login_tests')

        include_context 'remote user logins', host
      end
    end
  end
end
