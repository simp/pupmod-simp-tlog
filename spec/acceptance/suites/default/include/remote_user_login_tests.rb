# These tests need to be run in a couple of different scenarios so they have
# been pulled aside for reuse
shared_context 'remote user logins' do |host|
  require_relative('../lib/util')

  include TlogTestUtil

  context 'user' do
    let(:hidepid) {
      _hidepid = false

      if on(host, 'findmnt -n /proc').output.strip =~ /hidepid=(\d+)/
        if $1 != '0'
          _hidepid = true
        end
      end

      _hidepid
    }

    let(:ssh_ip) { host[:ip] }
    let(:ssh_port) { host.options[:ssh][:port] }

    let(:test_pass) { 'Test passw0rd @f some l3ngth' }
    let(:test_pass_hash) {
      require 'digest/sha2'
      test_pass.crypt('$6$' + rand(36**8).to_s(36))
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

    let(:hieradata_group) {{
       'tlog::rec_session::shell_hook_users' => [
         "%#{test_user}"
       ]
    }}

    # Make sure we didn't break root!
    context 'root' do
      let(:test_user) { 'root' }

      it 'should set the user password' do
        on(host, %(puppet resource user #{test_user} password='#{test_pass_hash}'))
      end

      it 'should successfully login' do
        session_info = local_ssh(ssh_ip, ssh_port, test_user, test_pass)
        expect(session_info[:output]).to_not match(/TLog Error/)
        expect(session_info[:success]).to be true
      end

      it 'should run puppet' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should successfully login' do
        session_info = local_ssh(ssh_ip, ssh_port, test_user, test_pass)
        expect(session_info[:output]).to_not match(/TLog Error/)
        expect(session_info[:success]).to be true
      end
    end

    context 'test_user' do
      let(:test_user) { 'test_user' }

      ['bash', 'tcsh'].each do |shell|

        context "with #{shell} as the shell" do
          it 'should create the test user with a password' do
            on(host, %(puppet resource user #{test_user} password='#{test_pass_hash}' managehome=true shell='/bin/#{shell}'))
          end

          it 'should successfully login' do
            session_info = local_ssh(ssh_ip, ssh_port, test_user, test_pass)
            expect(session_info[:output]).to_not match(/TLog Error/)
            expect(session_info[:success]).to be true
          end

          it 'should run puppet' do
            set_hieradata_on(host, hieradata)
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          # The csh wrapper has much looser constraints overall due to the nature of the shell
          if shell == 'bash'
            it 'should change the user shell to /usr/bin/tlog-rec-session' do
              on(host, %(puppet resource user #{test_user} shell='/usr/bin/tlog-rec-session'))
            end
          end

          it 'should successfully login' do
            session_info = local_ssh(ssh_ip, ssh_port, test_user, test_pass)
            expect(session_info[:output]).to_not match(/TLog Error/)
            expect(session_info[:success]).to be true
          end

          context 'when restricting by group' do
            shared_examples_for 'a group test' do
              it 'should run puppet' do
                set_hieradata_on(host, hieradata_group)
                apply_manifest_on(host, manifest, :catch_failures => true)
              end

              it "should change the user shell to /bin/#{shell}" do
                on(host, %(puppet resource user #{test_user} shell='/bin/#{shell}'))
              end

              it 'should attempt to login' do
                session_info = local_ssh(ssh_ip, ssh_port, test_user, test_pass)
                expect(session_info[:output]).to_not match(/TLog Error/)
                expect(session_info[:success]).to be true
              end
            end

            context 'primary group' do
              it_behaves_like 'a group test'
            end

            context 'secondary group' do
              let(:secondary_group) { 'other_test_group' }

              let(:hieradata_group) {{
                 'tlog::rec_session::shell_hook_users' => [
                   "%#{secondary_group}"
                 ]
              }}

              it 'should add a secondary group to the test user' do
                on(host, %{puppet resource group #{secondary_group} ensure=present})
                on(host, %{puppet resource user #{test_user} groups='#{secondary_group}'})
              end

              it_behaves_like 'a group test'
            end
          end
        end
      end
    end
  end
end
