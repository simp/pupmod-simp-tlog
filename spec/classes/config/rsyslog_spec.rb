require 'spec_helper'

describe 'tlog::config::rsyslog' do
  shared_examples_for 'a structured module' do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to create_class(class_name) }
    it { is_expected.to create_class('rsyslog') }

    it {
      is_expected.to create_rsyslog__rule__local('XX_tlog').with({
                                                                   rule: current_class[:match_rule],
        target_log_file: current_class[:log_file],
        stop_processing: current_class[:stop_processing]
                                                                 })
    }
  end

  context 'supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "on #{os}" do
        let(:facts) do
          os_facts
        end

        let(:current_class) do
          catalogue.resource("Class[#{class_name}]")
        end

        context 'without any parameters' do
          let(:params) { {} }

          it_behaves_like 'a structured module'
        end

        context 'when enabling logrotate' do
          let(:params) do
            {
              logrotate: true
            }
          end

          it_behaves_like 'a structured module'
          it {
            is_expected.to create_logrotate__rule('tlog').with({
                                                                 log_files: [ current_class[:log_file] ],
              create: current_class[:logrotate_create],
              missingok: current_class[:logrotate_options]['missingok'],
              lastaction_restart_logger: current_class[:logrotate_options]['lastaction_restart_logger']
                                                               })
          }
        end
      end
    end
  end
end
