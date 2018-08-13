require 'spec_helper_acceptance'
require 'net/ssh'

test_name 'tlog::rec_session with hidepid'

describe 'tlog::rec_session' do
  let(:test_user_pass) { 'Test passw0rd @f some l3ngth' }
  let(:test_pass_hash) {
    require 'digest/sha2'
    test_user_pass.crypt('$6$' + rand(36**8).to_s(36))
  }

  let(:manifest) {
    <<-EOS
      include 'tlog::rec_session'
    EOS
  }

  let(:hieradata) {{
     'tlog::rec_session::shell_hook_users' => [
       test_user
     ]
  }}

  hosts.each do |host|
    ssh_info = host.connection.instance_variable_get('@ssh').options

    context "on #{host}" do
      let(:ssh_test) {
        require 'timeout'
        require 'pty'
        require 'expect'

        output = ''

        begin
          Timeout::timeout(5) do
            PTY.spawn("ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l #{test_user} -p #{ssh_info[:port]} #{ssh_info[:host_name]}") do |r, w, pid|
              begin
                r.expect(/sword: /) { |msg| w.puts(test_user_pass) }

                r.sync

                r.each_line do |l|
                  output += l
                end
              rescue Errno::EIO
                # This happens when you're out of lines
              end
            end
          end
        rescue Timeout::Error
          # Catching a kill on hang due to a successful
          # shell connection
        end

        output
      }

      context 'with hidepid enabled' do
        it 'should remount /proc' do
          on(host, 'mount -o remount,hidepid=2,rw,nosuid,nodev,noexec,relatime /proc')
        end

        it 'should set the abilty to login via password' do
          on(host, %(sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config))
          on(host, %(echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config))
          on(host, %(sed -i '/PermitRootLogin/d' /etc/ssh/sshd_config))
          on(host, %(echo "PermitRootLogin yes" >> /etc/ssh/sshd_config))
          on(host, %(puppet resource service sshd ensure=stopped && puppet resource service sshd ensure=running))
        end

        # Make sure we didn't break root!
        context 'as root' do
          let(:test_user) { 'root' }

          it 'should create the test user with a password' do
            on(host, %(puppet resource user #{test_user} password='#{test_pass_hash}' managehome=true))
          end

          it 'should successfully login' do
            expect(ssh_test).to_not match(/TLog Error/)
          end

          it 'should run puppet' do
            set_hieradata_on(host, hieradata)
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should successfully login' do
            expect(ssh_test).to_not match(/TLog Error/)
          end
        end

        context 'as the test user' do
          let(:test_user) { 'test_user' }

          it 'should create the test user with a password' do
            on(host, %(puppet resource user #{test_user} password='#{test_pass_hash}' managehome=true))
          end

          it 'should successfully login' do
            expect(ssh_test).to_not match(/TLog Error/)
          end

          it 'should run puppet' do
            set_hieradata_on(host, hieradata)
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should fail to login due to tlog' do
            expect(ssh_test).to match(/TLog Error/)
          end
        end
      end
    end
  end
end
