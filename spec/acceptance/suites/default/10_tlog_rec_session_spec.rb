require 'spec_helper_acceptance'

test_name 'tlog::rec_session'

describe 'tlog::rec_session' do
  let(:manifest) do
    <<-EOS
      include 'tlog::rec_session'
    EOS
  end

  let(:hieradata) do
    {
      'tlog::manage_rsyslog' => true,
   'tlog::config::rsyslog::logrotate' => true
    }
  end

  let(:not_root_enforcing_hieradata) do
    hieradata.merge({
                      'tlog::rec_session::shell_hook_users' => [ ]
                    })
  end

  hosts.each do |host|
    context "on #{host}" do
      context 'when not enforcing for "root"' do
        # Using puppet_apply as a helper
        it 'works with no errors' do
          set_hieradata_on(host, not_root_enforcing_hieradata)
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'does not log any user sessions' do
          content = on(host, %(sudo su - -c 'ls /tmp')).output
          expect(content).not_to match(%r{session is being recorded}m)
        end
      end

      context 'when default parameters (enforcing for "root")' do
        # Using puppet_apply as a helper
        it 'works with no errors' do
          set_hieradata_on(host, hieradata)
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'logs "root" sessions' do
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
          expect(content).to match(%r{session is being recorded}m)
        end
      end

      require_relative('include/remote_user_login_tests')

      include_context 'remote user logins', host
    end
  end
end
