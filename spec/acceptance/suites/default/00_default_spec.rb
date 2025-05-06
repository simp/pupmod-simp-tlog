require 'spec_helper_acceptance'

test_name 'tlog'

describe 'tlog' do
  let(:manifest) do
    <<-EOS
      # Need to use the SSH module for FIPS testing
      include 'ssh'
      include 'tlog'
    EOS
  end

  let(:hieradata) do
    {
      # We'll be logging in directly in subsequent tests
      'ssh::server::conf::permitrootlogin' => true,
   'ssh::server::conf::passwordauthentication' => true,
   'ssh::server::conf::authorizedkeysfile'     => '.ssh/authorized_keys',
   'tlog::manage_rsyslog'                      => true,
   'tlog::config::rsyslog::logrotate'          => true
    }
  end

  hosts.each do |host|
    context "on #{host}" do
      context 'default parameters' do
        it 'enables SIMP dependencies repo for tlog package' do
          # tlog is incuded for EL8, but this shouldn't cause issues
          install_simp_repos(host)
        end

        it 'has the required test shells' do
          host.install_package('bash')
          host.install_package('tcsh')
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          set_hieradata_on(host, hieradata)
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'has tlog installed' do
          expect(check_for_package(host, 'tlog')).to be true
        end
      end
    end
  end
end
