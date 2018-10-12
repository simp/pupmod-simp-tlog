require 'spec_helper_acceptance'

test_name 'tlog::rec_session'

describe 'tlog::rec_session' do
  let(:manifest) {
    <<-EOS
      include 'tlog::rec_session'
    EOS
  }

  let(:hieradata) {{
    'tlog::manage_rsyslog'             => true,
    'tlog::config::rsyslog::logrotate' => true
  }}

  let(:not_root_enforcing_hieradata) {
   hieradata.merge({
     'tlog::rec_session::shell_hook_users' => [ ]
   })
  }

  hosts.each do |host|
    context "on #{host}" do
      context 'when not enforcing for "root"' do
        # Using puppet_apply as a helper
        it 'should work with no errors' do
          set_hieradata_on(host, not_root_enforcing_hieradata)
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should not log any user sessions' do
          content = on(host, %(sudo su - -c 'ls /tmp')).output
          expect(content).not_to match(/session is being recorded/m)
        end
      end

      context 'when default parameters (enforcing for "root")' do
        # Using puppet_apply as a helper
        it 'should work with no errors' do
          set_hieradata_on(host, hieradata)
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should log "root" sessions' do
          test_script = <<-EOM
#!/opt/puppetlabs/puppet/bin/ruby

require 'pty'
require 'expect'

PTY.spawn('sudo su -') do |input, output|
  input.expect(/#\s*$/) do |data|
    puts data
    output.puts('exit') unless data.nil?
  end
end
          EOM

          test_script_tgt = '/usr/bin/beaker_shell_test'

          create_remote_file(host, test_script_tgt, test_script)
          on(host, %(chmod +x #{test_script_tgt}))

          content = on(host, test_script_tgt).output
          expect(content).to match(/session is being recorded/m)
        end
      end

      require_relative('include/remote_user_login_tests')

      include_context 'remote user logins', host
    end
  end
end
