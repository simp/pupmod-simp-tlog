module TlogTestUtil
  # Relax the rsyslog systemd service sandboxing on container SUTs.
  #
  # tlog pulls in the simp/rsyslog dependency, whose service uses the
  # distribution rsyslog.service unit. On EL8+ that unit ships aggressive
  # sandboxing (SystemCallFilter, RestrictAddressFamilies, ProtectKernelModules,
  # MemoryDenyWriteExecute, etc.). Under a restrictive container runtime -- such
  # as the privileged-but-seccomp/AppArmor-confined Docker host used by GitHub
  # Actions -- those directives cause `rsyslogd` to exit 1 immediately on start,
  # producing the misleading "Systemd start for rsyslog failed!" error even
  # though the rsyslog configuration itself is valid. This does not reproduce on
  # a permissive local Docker host, which is why local runs pass while CI fails
  # across every nodeset.
  #
  # Bare metal / full VMs are unaffected, so we only install the drop-in when the
  # SUT reports it is running inside a container. The override is a no-op where
  # the stock unit already starts cleanly, so it never weakens the assertion that
  # the rsyslog service actually comes up -- the service still has to start and
  # stay running for the suite to pass.
  #
  # @param host [Beaker::Host]
  #   The SUT to configure
  def relax_rsyslog_sandboxing_on_containers(host)
    # virtual fact reports 'docker'/'container_other'/etc. inside containers
    virtual = fact_on(host, 'virtual').to_s
    return unless virtual.match?(%r{docker|container|lxc|podman|systemd_nspawn})

    dropin_dir = '/etc/systemd/system/rsyslog.service.d'
    on(host, "mkdir -p #{dropin_dir}")
    create_remote_file(host, "#{dropin_dir}/99-beaker-container.conf", <<~DROPIN)
      [Service]
      # Managed by the tlog acceptance suite: relax rsyslog.service sandboxing
      # that prevents rsyslogd from starting under restrictive container runtimes
      # (e.g. GitHub Actions Docker). Empty values reset the inherited settings.
      SystemCallFilter=
      RestrictAddressFamilies=
      RestrictNamespaces=no
      ProtectKernelModules=no
      ProtectKernelTunables=no
      ProtectControlGroups=no
      ProtectHome=no
      PrivateDevices=no
      MemoryDenyWriteExecute=no
    DROPIN
    on(host, 'systemctl daemon-reload')
  end

  # Ensure the `hostname` command is available on the SUT.
  #
  # The tlog profile drop-ins (templates/etc/profile.d/tlog.{sh,csh}.epp) gate
  # session recording on `hostname -f` succeeding:
  #
  #   if hostname -f >& /dev/null; then exec $TLOG_CMD
  #   elif [ $UID -eq 0 ]; then echo 'Tlog hostname lookup failed, emergency bypass for root'
  #   else exec echo 'Tlog hostname lookup failed - access denied'
  #
  # On minimal EL8+ images the `hostname` binary (from the `hostname` package) is
  # not installed by default. When it is missing the command exits non-zero, so
  # tlog takes the bypass/deny branch and never starts recording -- which makes
  # the "logs root sessions" assertions fail nondeterministically depending on
  # whether some other package happened to pull in `hostname` first. Installing it
  # explicitly makes the recording behavior deterministic across the OS matrix.
  #
  # @param host [Beaker::Host]
  #   The SUT to configure
  def ensure_hostname_command(host)
    host.install_package('hostname')
  end

  # Helper method for using accessing a host and immediately logging out.
  #
  # This used to be native SSH but was switched to Net::SSH due to
  # incompatibilities as underlying OS versions progressed.
  #
  # @param host [String]
  #   The host to which to connect
  #
  # @param port [String]
  #   The port to use for the connection
  #
  # @param user [String]
  #   The user to login as
  #
  # @param password [String]
  #   The password to use
  #
  # @param timeout [Integer]
  #   Session timeout in seconds
  #
  # @param command [String]
  #   The command to run
  #
  # @return [Hash]
  #   :success [Boolean] => Whether or not the command was successful
  #   :output [String]   => The output from the session
  def local_ssh(host, port, user, password, timeout = 5)
    require 'timeout'
    require 'net/ssh'

    to_return = {
      success: false,
      output: []
    }

    ssh_opts = {
      # Ignore ssh-agent
      keys_only: true,
      non_interactive: true,
      password: password,
      port: port,
      timeout: timeout,
      user_known_hosts_file: ['/dev/null'],
      verify_host_key: :never,
      # For FIPS testing
      encryption: 'aes256-ctr',
      hmac: ['hmac-sha2-256', 'hmac-sha1']
    }

    begin
      Net::SSH.start(host, user, ssh_opts) do |ssh|
        ssh.open_channel do |channel|
          channel.on_data do |_ch, data|
            to_return[:output] << data
          end
          channel.on_extended_data do |_ch, data|
            to_return[:output] << data
          end
          channel.request_pty
          channel.send_channel_request 'shell'
        end

        begin
          Timeout.timeout(10) do
            ssh.loop
          end
        rescue
          ssh.close
        end
      end
    rescue => e
      logger.error("Password prompt never received for '#{user}@#{host}:#{port}' => #{e}")
    end

    to_return[:output] = to_return[:output].flatten.compact.map(&:strip).join("\n")
    to_return[:success] = !%r{(#|\$)\s*$}m.match(to_return[:output]).nil?

    to_return
  end
end
