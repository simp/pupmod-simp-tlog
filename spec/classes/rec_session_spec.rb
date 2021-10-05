require 'spec_helper'

describe 'tlog::rec_session' do
  shared_examples_for 'a structured module' do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to create_class('tlog::rec_session') }
    it { is_expected.to create_class('tlog') }
    it { is_expected.to create_class('tlog::install').that_comes_before('File[/etc/tlog/tlog-rec-session.conf]') }

    it { is_expected.to create_file('/etc/tlog/tlog-rec-session.conf').with(file_attrs.merge({:ensure => 'file'})) }

    it {
      res = catalogue.resource('File[/etc/tlog/tlog-rec-session.conf]')
      expect(JSON.parse(res[:content])).to eq conf_content
    }

    it {
      tlog_users_var = %(TLOG_USERS="#{current_class[:shell_hook_users_file]}")
      tlog_cmd_var = %(TLOG_CMD="#{current_class[:shell_hook_cmd]}")

      is_expected.to create_file('/etc/profile.d/00-simp-tlog.sh').with(file_attrs)
      is_expected.to create_file('/etc/profile.d/00-simp-tlog.sh').with_content(%r(#{tlog_users_var}))
      is_expected.to create_file('/etc/profile.d/00-simp-tlog.sh').with_content(%r(#{tlog_cmd_var}))
    }

    it {
      tlog_users_var = %(set TLOG_USERS="#{current_class[:shell_hook_users_file]}")
      tlog_cmd_var = %(set TLOG_CMD="#{current_class[:shell_hook_cmd]}")

      is_expected.to create_file('/etc/profile.d/00-simp-tlog.csh').with(file_attrs)
      is_expected.to create_file('/etc/profile.d/00-simp-tlog.csh').with_content(%r(#{tlog_users_var}))
      is_expected.to create_file('/etc/profile.d/00-simp-tlog.csh').with_content(%r(#{tlog_cmd_var}))
    }

    it { is_expected.to create_file('/etc/security/tlog.users').with_content("#{current_class[:shell_hook_users].join("\n")}\n") }
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

        if os_facts[:systemd]
          let(:conf_content){{
            'shell'  => '/bin/bash',
            'writer' => 'journal',
            'log'    => {
              'input' => false
            }
          }}
        else
          let(:conf_content){{
            'shell'  => '/bin/bash',
            'writer' => 'syslog',
            'log'    => {
              'input' => false
            }
          }}
        end

        let(:file_attrs){{
          :ensure  => 'file',
          :owner   => 'root',
          :group   => 'root',
          :mode    => '0644'
        }}

        context 'without any parameters' do
          let(:params) {{ }}

          it_behaves_like 'a structured module'

          it { is_expected.to create_class('tlog::install').that_comes_before('File[/etc/profile.d/00-simp-tlog.sh]') }
          it { is_expected.to create_class('tlog::install').that_comes_before('File[/etc/profile.d/00-simp-tlog.csh]') }
          it { is_expected.to create_class('tlog::install').that_comes_before('File[/etc/security/tlog.users]') }

        end

        context 'with a file writer' do
          let(:params) {{
            :options => {
              'writer' => 'file',
              'file'   => {
                'path' => '/var/log/tlog.log'
              }
            }
          }}

#          it_behaves_like 'a structured module'

          it { is_expected.to create_file('/var/log/tlog.log')
            .with(
              :ensure => 'file',
              :owner  => 'tlog',
              :group  => 'tlog',
              :mode   => '0640',
            )
          }
        end

        context 'custom_options' do
          let(:params) {{
            :custom_options => {
              'shell'  => '/bin/sh',
              'writer' => 'we do not verify these'
            }
          }}

          let(:conf_content){{
            'shell'  => params[:custom_options]['shell'],
            'writer' => params[:custom_options]['writer'],
            'log'    => {
              'input' => false
            }
          }}

          it_behaves_like 'a structured module'
        end

        context 'shell_hook' do
          context 'disabled' do
            let(:params){{
              :shell_hook => false
            }}

            let(:file_attrs){{
              :ensure  => 'absent'
            }}

            it_behaves_like 'a structured module'
          end

          context 'users defined' do
            let(:params){{
              :shell_hook_users => ['root', 'bob', '%alice']
            }}

            it_behaves_like 'a structured module'
          end
        end
      end
    end
  end
end
