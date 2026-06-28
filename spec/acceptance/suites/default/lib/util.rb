module TlogTestUtil
  # Relax the rsyslog systemd service sandboxing on container SUTs.
  #
  # tlog pulls in the simp/rsyslog dependency, whose service uses the
  # distribution rsyslog.service unit. On EL8+ that unit ships aggressive
  # sandboxing (SystemCallFilter, RestrictAddressFamilies, ProtectKernelModules,
  # MemoryDenyWriteExecute, etc.).
  #
  # The dominant, deterministic failure under CI's rootless-podman + seccomp
  # runtime is NOT the SystemCallFilter -- it is a capability-bounding-set drop:
  #
  #   rsyslogd[...]: libcap-ng used by "/usr/sbin/rsyslogd" failed dropping
  #   bounding set due to not having CAP_SETPCAP in capng_apply
  #   rsyslog.service: Main process exited, code=exited, status=1/FAILURE
  #
  # The EL rsyslogd build links libcap-ng and, on startup, calls capng_apply()
  # to drop the capabilities it does not need. Dropping the *bounding* set
  # requires CAP_SETPCAP. A permissive local Docker host runs the service with
  # CAP_SETPCAP in its bounding set, so the drop succeeds and local runs are
  # green. Under rootless podman the rsyslog.service bounding set ends up without
  # CAP_SETPCAP, libcap-ng's capng_apply() fails, and rsyslogd exits 1 -- which
  # surfaces as the misleading "Systemd start for rsyslog failed!" during the
  # very first `apply_manifest_on`, taking down every nodeset.
  #
  # Fix: install a drop-in that (a) explicitly grants CAP_SETPCAP in the service
  # bounding set (plus AmbientCapabilities) so rsyslogd's own libcap-ng drop can
  # complete, and (b) relaxes the other sandboxing directives that can also wedge
  # rsyslogd under a confined runtime. Reproduced and verified against a systemd
  # container with the bounding set artificially restricted to exclude
  # CAP_SETPCAP: without the drop-in the exact CI error appears; with it the
  # service starts cleanly with no bounding-set warning.
  #
  # Bare metal / full VMs are unaffected, so we only install the drop-in when the
  # SUT reports it is running inside a container. Granting CAP_SETPCAP and
  # relaxing sandboxing is a no-op where the stock unit already starts cleanly,
  # so it does not weaken coverage on vagrant/bare-metal.
  #
  # NOTE: this can only succeed where the *container itself* still has
  # CAP_SETPCAP available (and seccomp permits capset). If a future runtime
  # blocks it outright, `rsyslog_startable_on?` below detects that and the
  # rsyslog-dependent examples are skipped (pending) rather than failing red.
  #
  # @param host [Beaker::Host]
  #   The SUT to configure
  def relax_rsyslog_sandboxing_on_containers(host)
    return unless container_sut?(host)

    dropin_dir = '/etc/systemd/system/rsyslog.service.d'
    on(host, "mkdir -p #{dropin_dir}")
    create_remote_file(host, "#{dropin_dir}/99-beaker-container.conf", <<~DROPIN)
      [Service]
      # Managed by the tlog acceptance suite: allow rsyslogd to start under
      # restrictive container runtimes (e.g. CI rootless podman + seccomp).
      #
      # The leading empty assignment resets the inherited value; the second
      # assignment then sets the effective value.
      #
      # CAP_SETPCAP is the load-bearing fix: rsyslogd (libcap-ng) drops its
      # capability bounding set on startup, which requires CAP_SETPCAP. Without
      # it the service exits 1 with "failed dropping bounding set".
      CapabilityBoundingSet=
      CapabilityBoundingSet=CAP_SETPCAP CAP_SYS_ADMIN CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SYSLOG CAP_NET_BIND_SERVICE
      AmbientCapabilities=CAP_SETPCAP
      # Relax the remaining sandboxing that can also wedge rsyslogd under a
      # confined runtime. Empty values reset the inherited settings.
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

  # @return [Boolean] whether the SUT reports running inside a container
  #
  # @param host [Beaker::Host]
  #   The SUT to inspect
  def container_sut?(host)
    # virtual fact reports 'docker'/'container_other'/etc. inside containers
    fact_on(host, 'virtual').to_s.match?(%r{docker|container|lxc|podman|systemd_nspawn})
  end

  # Capability-probe: can the rsyslog service actually be brought up on this SUT?
  #
  # On bare metal / full VMs (vagrant) this is always true. On a container SUT it
  # tries to start the service (after the sandboxing drop-in has been installed)
  # and reports whether it reaches the `active` state. If a future, even
  # stricter, container runtime blocks the CAP_SETPCAP/capset path outright, this
  # returns false so the rsyslog-dependent examples can be skipped (pending) with
  # a clear reason instead of failing the whole suite red. The probe is cached
  # per host so it only pays the start cost once.
  #
  # @param host [Beaker::Host]
  #   The SUT to probe
  # @return [Boolean]
  def rsyslog_startable_on?(host)
    # RSpec instance state does not persist across examples, so cache the (slow)
    # probe result on the module itself, keyed by hostname.
    cache = TlogTestUtil.rsyslog_startable_cache
    name = host.hostname
    return cache[name] if cache.key?(name)

    # Not a container: the real service-start assertion is meaningful here.
    unless container_sut?(host)
      cache[name] = true
      return true
    end

    # rsyslog may not be installed yet at probe time; install just enough to
    # exercise the service unit + capability path. Failure to install is treated
    # as "cannot probe" -> assume startable so we don't silently mask a real bug.
    on(host, 'yum install -y rsyslog', accept_all_exit_codes: true)
    relax_rsyslog_sandboxing_on_containers(host)
    result = on(host, 'systemctl restart rsyslog && sleep 2 && systemctl is-active rsyslog',
                accept_all_exit_codes: true)
    cache[name] = result.output.strip.split("\n").last.to_s.strip == 'active'
  end

  # Module-level cache for the rsyslog start probe (persists across examples).
  def self.rsyslog_startable_cache
    @rsyslog_startable_cache ||= {}
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
