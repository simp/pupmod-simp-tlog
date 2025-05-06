require 'spec_helper'

describe 'tlog' do
  shared_examples_for 'a structured module' do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to create_class('tlog') }
    it { is_expected.to create_class('tlog::install') }
  end

  context 'supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "on #{os}" do
        let(:facts) do
          os_facts
        end

        context 'without any parameters' do
          let(:params) { {} }

          it_behaves_like 'a structured module'
        end

        context 'when managing syslog' do
          let(:params) do
            {
              manage_rsyslog: true
            }
          end

          it_behaves_like 'a structured module'
          it { is_expected.to create_class('tlog::config::rsyslog') }
        end
      end
    end
  end
end
