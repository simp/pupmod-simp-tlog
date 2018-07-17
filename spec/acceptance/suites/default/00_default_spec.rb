require 'spec_helper_acceptance'

test_name 'tlog'

describe 'tlog' do
  let(:manifest) {
    <<-EOS
      include 'tlog'
    EOS
  }

  let(:hieradata) {{
    'tlog::manage_rsyslog'             => true,
    'tlog::config::rsyslog::logrotate' => true
  }}

  hosts.each do |host|
    context "on #{host}" do
      context 'default parameters' do
        # Using puppet_apply as a helper
        it 'should work with no errors' do
          set_hieradata_on(host, hieradata)
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should have tlog installed' do
          expect(check_for_package(host, 'tlog')).to be true
        end
      end
    end
  end
end
