module TlogTestUtil
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
