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
        it 'enables a package repository for the tlog package' do
          # The `tlog`, `rsyslog`, and `logrotate` packages all ship in the OS
          # repositories (AppStream/BaseOS) on EL8+, so the SIMP community repo
          # is not strictly required here. However, a `simp-release-community`
          # RPM is currently only published for EL7/EL8; on EL9+ that URL 404s.
          # Install the SIMP repos where the release RPM is available and fall
          # back to EPEL elsewhere so the suite runs across the full OS matrix.
          release = fact_on(host, 'os.release.major').to_s
          if ['7', '8'].include?(release)
            install_simp_repos(host)
          else
            enable_epel_on(host)
          end
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
