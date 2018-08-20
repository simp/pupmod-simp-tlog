module TlogTestUtil
  # Helper method for using a local SSH session for accessing a host and
  # immediately logging out. This is useful for capturing output messages that
  # cannot otherwise consistently be accessed via Net::SSH.
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
  # @return [Hash]
  #   :success [Boolean] => Whether or not the command was successful
  #   :output [String]   => The output from the session
  def local_ssh(host, port, user, password, timeout=5)
    require 'timeout'
    require 'pty'
    require 'expect'

    to_return = {
      :success => false,
      :output  => []
    }

    begin
      Timeout::timeout(timeout) do
        # Cihper and HMAC set for the FIPS tests
        PTY.spawn("ssh -tt -c aes256-ctr -m hmac-sha2-256,hmac-sha1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l #{user} -p #{port} #{host}") do |r, w, pid|
          begin
            r.expect(/password: /i) { |msg| w.puts(password) }

            begin
              Timeout::timeout(3) do
                while true
                  to_return[:output] << r.expect(/(#|\$|\n)\s*$/)
                end
              end
            rescue Errno::EIO, Timeout::Error
              # This determines that no additional input is forthcoming
            end
          rescue Errno::EIO
            logger.error("Password prompt never received for '#{user}@#{host}:#{port}'")
          end
        end
      end
    rescue Timeout::Error
      # Catching a kill on hang
    end

    to_return[:output] = to_return[:output].flatten.compact.map(&:strip).join("\n")
    to_return[:success] = !%r{(#|\$)\s*$}m.match(to_return[:output]).nil?
    return to_return
  end
end
