# These tests need to be run in a couple of different scenarios so they have
# been pulled aside for reuse
shared_context 'remote user logins' do |host, ssh_info|
  require_relative('../lib/util')

  include TlogTestUtil

  context 'user' do
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

    # Make sure we didn't break root!
    context 'root' do
      let(:test_user) { 'root' }

      it 'should create the test user with a password' do
        on(host, %(puppet resource user #{test_user} password='#{test_pass_hash}'))
      end

      it 'should successfully login' do
        session_info = local_ssh(ssh_info[:host_name], ssh_info[:port], test_user, test_pass)
        expect(session_info[:output]).to_not match(/TLog Error/)
        expect(session_info[:success]).to be true
      end

      it 'should run puppet' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should successfully login' do
        session_info = local_ssh(ssh_info[:host_name], ssh_info[:port], test_user, test_pass)
        expect(session_info[:output]).to_not match(/TLog Error/)
        expect(session_info[:success]).to be true
      end
    end

    context 'test_user' do
      let(:test_user) { 'test_user' }

      context 'with bash as the shell' do
        it 'should create the test user with a password' do
          on(host, %(puppet resource user #{test_user} password='#{test_pass_hash}' managehome=true shell='/bin/bash'))
        end

        it 'should successfully login' do
          session_info = local_ssh(ssh_info[:host_name], ssh_info[:port], test_user, test_pass)
          expect(session_info[:output]).to_not match(/TLog Error/)
          expect(session_info[:success]).to be true
        end

        it 'should run puppet' do
          set_hieradata_on(host, hieradata)
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should fail to login due to tlog' do
          session_info = local_ssh(ssh_info[:host_name], ssh_info[:port], test_user, test_pass)
          expect(session_info[:output]).to match(/TLog Error/)
          expect(session_info[:success]).to be false
        end

        it 'should change the user shell to /usr/bin/tlog-rec-session' do
          on(host, %(puppet resource user #{test_user} shell='/usr/bin/tlog-rec-session'))
        end

        it 'should successfully login' do
          session_info = local_ssh(ssh_info[:host_name], ssh_info[:port], test_user, test_pass)
          expect(session_info[:output]).to_not match(/TLog Error/)
          expect(session_info[:success]).to be true
        end
      end

      # The csh wrapper has much looser constraints overall due to the nature of the shell
      context 'with tcsh as the shell' do
        it 'should set the shell to /bin/tcsh' do
          on(host, %(puppet resource user #{test_user} shell='/bin/tcsh'))
        end

        it 'should successfully login' do
          session_info = local_ssh(ssh_info[:host_name], ssh_info[:port], test_user, test_pass)
          expect(session_info[:output]).to_not match(/TLog Error/)
          expect(session_info[:success]).to be true
        end
      end
    end
  end
end