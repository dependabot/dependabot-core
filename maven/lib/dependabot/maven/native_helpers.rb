# typed: strict
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"
require "uri"
require "sorbet-runtime"
require "nokogiri"
require "dependabot/errors"
require "dependabot/command_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Maven
    module NativeHelpers
      extend T::Sig

      # Matches Maven's "Could not transfer artifact" failures, capturing the
      # repository URL and HTTP status so we can classify auth vs. other errors.
      TRANSFER_FAILURE_REGEX =
        %r{Could not transfer artifact (?<artifact>[^ ]+) from/to (?<repository_name>[^ ]+) \((?<repository_url>[^ ]+)\): status code: (?<status_code>[0-9]+)} # rubocop:disable Layout/LineLength

      # Matches Maven's "Plugin ... could not be resolved" failures, used to
      # detect when the wrapper plugin itself is unavailable behind the proxy.
      WRAPPER_PLUGIN_UNRESOLVED_REGEX =
        /Plugin org\.apache\.maven\.plugins:maven-wrapper-plugin[^ ]* .*could not be resolved/

      # Upper bound on the length of the Maven error summary included in raised errors,
      # to avoid oversized error payloads while retaining the relevant failure detail.
      MAX_ERROR_SUMMARY_LENGTH = 2_000

      # Matches ANSI/VT100 control sequences. Maven can be configured to emit colored
      # output (e.g. `-Dstyle.color=always`), wrapping markers like `[ERROR]` in escape
      # codes; we strip these so classification and the surfaced summary see plain text.
      ANSI_ESCAPE_REGEX = %r{\e\[[0-9;?]*[ -/]*[@-~]}

      # Bounded inactivity timeout for the wrapper download. `run_shell_command`'s watchdog
      # resets on output, and with transfer progress restored a healthy download keeps it
      # alive, so this only trips on genuine silence — well below the 900s DEFAULT.
      WRAPPER_DOWNLOAD_TIMEOUT = CommandHelpers::TIMEOUTS::LONG_RUNNING

      pom_path = File.join(__dir__, "pom.xml")

      version = File.open(pom_path) do |f|
        doc = Nokogiri::XML(f)
        doc.at_xpath("//project/properties/maven-dependency-plugin.version")&.text
      end

      DEPENDENCY_PLUGIN_VERSION = T.let(version, T.nilable(String))

      sig do
        params(file_name: String).void
      end
      def self.run_mvn_dependency_tree_plugin(file_name)
        raise DependabotError, "Could not resolve maven-dependency-plugin version" unless DEPENDENCY_PLUGIN_VERSION

        proxy_url = URI.parse(ENV.fetch("HTTPS_PROXY"))
        stdout, _, status = Open3.capture3(
          { "PROXY_HOST" => proxy_url.host },
          "mvn",
          "dependency:#{DEPENDENCY_PLUGIN_VERSION}:tree",
          "-DoutputFile=#{file_name}",
          "-DoutputType=json",
          "-e"
        )
        Dependabot.logger.info("mvn dependency:tree output: STDOUT:#{stdout}")
        handle_tool_error(stdout) unless status.success?
      end

      sig { params(output: String).void }
      def self.handle_tool_error(output)
        if (match = output.match(TRANSFER_FAILURE_REGEX)) &&
           (match[:status_code] == "403" || match[:status_code] == "401")
          raise Dependabot::PrivateSourceAuthenticationFailure, match[:repository_url]
        end

        raise DependabotError, "mvn CLI failed with an unhandled error"
      end

      # Runs the Maven Wrapper plugin in the given directory to regenerate
      # wrapper scripts and artifacts for the specified Maven distribution version.
      #
      # Plugin version strategy:
      #   Uses the fully-qualified coordinate
      #   org.apache.maven.plugins:maven-wrapper-plugin:VERSION:wrapper
      #   rather than the shorthand `wrapper:wrapper`. This pins the exact plugin
      #   version instead of relying on Maven's plugin prefix resolution, which
      #   varies by settings.xml and could silently use a different version.
      sig do
        params(
          version: String,
          wrapper_plugin_version: String,
          env: T::Hash[String, String],
          distribution_type: String,
          registry_base: T.nilable(String),
          extra_args: T::Array[String],
          cwd: T.nilable(String)
        ).void
      end
      def self.run_mvnw_wrapper(
        version:,
        wrapper_plugin_version:,
        env:,
        distribution_type:,
        registry_base: nil,
        extra_args: [],
        cwd: nil
      )
        # Use the fully-qualified plugin goal so the exact plugin version is
        # invoked regardless of the project's plugin group configuration.
        plugin_goal = "org.apache.maven.plugins:maven-wrapper-plugin:" \
                      "#{wrapper_plugin_version}:wrapper"

        # Do NOT add `--no-transfer-progress`: Maven's transfer progress is the liveness signal
        # that keeps `run_shell_command`'s inactivity watchdog alive during a large download.
        # Suppressing it made a healthy-but-slow fetch look hung and get killed at the timeout.
        standard_args = [
          plugin_goal,
          "-Dmaven=#{version}",
          "-Dtype=#{distribution_type}"
        ] + extra_args

        # Pass the argument vector directly instead of a pre-joined shell string.
        # `run_shell_command` shell-escapes string commands internally, so building
        # the command with `Shellwords.join` here would double-escape arguments
        # (e.g. `-Dmaven=3.6.3` becoming `-Dmaven\=3.6.3`), which Maven then fails
        # to parse. An argument vector is executed without an intermediate shell.
        cmd = ["mvn"] + standard_args
        run_cwd = cwd && cwd != "." ? cwd : nil

        # Route the native `mvn`'s plugin/distribution resolution to the registry that served the
        # resolved version via a generated settings mirror; without it `mvn` falls back to Central
        # and hangs behind a no-egress registry. Absent when no version resolved, leaving the baked
        # Central default. The bounded timeout is explained on WRAPPER_DOWNLOAD_TIMEOUT.
        settings_file = registry_base && wrapper_settings_file(registry_base)
        settings_args = settings_file ? ["-s", T.must(settings_file.path)] : []
        begin
          output = SharedHelpers.run_shell_command(
            cmd + settings_args,
            env: env,
            cwd: run_cwd,
            timeout: WRAPPER_DOWNLOAD_TIMEOUT
          )
        ensure
          settings_file&.close! # deletes the temp file
        end
        Dependabot.logger.info("mvn wrapper output: STDOUT:#{output}")
        output
      rescue SharedHelpers::HelperSubprocessFailed => e
        # `run_shell_command` raises HelperSubprocessFailed on a non-zero exit, and the
        # updater sanitizes that into an opaque `SubprocessFailed` that only reports the
        # command and hides the real Maven output. Log the full output and re-raise a
        # classified Dependabot error so operators get an actionable message, mirroring
        # the `run_mvn_dependency_tree_plugin` path.
        Dependabot.logger.warn("mvn wrapper command failed:\n#{e.message}")
        handle_wrapper_error(e)
      end

      # Writes a temporary Maven settings file that keeps the proxy block and adds a
      # mirror pointing every external repository at the resolved base. Registry
      # auth still flows through the Dependabot proxy; no credentials are written here.
      # The caller is responsible for deleting the returned file (via `close!`).
      sig { params(registry_base: String).returns(Tempfile) }
      def self.wrapper_settings_file(registry_base)
        file = Tempfile.new(["dependabot-mvn-wrapper-settings", ".xml"])
        file.write(wrapper_settings_xml(registry_base))
        file.close
        file
      end

      # Builds the settings XML used for the wrapper invocation: the same proxy block as
      # the baked settings (auth is injected by the proxy) plus a `mirrorOf=external:*`
      # mirror so plugin, transitive POM, and distribution resolution all route through
      # the resolved base instead of Central.
      sig { params(registry_base: String).returns(String) }
      def self.wrapper_settings_xml(registry_base)
        <<~XML
          <settings>
            <proxies>
              <proxy>
                <id>dependabot-proxy</id>
                <active>true</active>
                <protocol>http</protocol>
                <host>${env.PROXY_HOST}</host>
                <port>1080</port>
              </proxy>
            </proxies>
            <mirrors>
              <mirror>
                <id>dependabot-wrapper-mirror</id>
                <mirrorOf>external:*</mirrorOf>
                <url>#{registry_base.encode(xml: :text)}</url>
              </mirror>
            </mirrors>
          </settings>
        XML
      end

      # Classifies a failed Maven Wrapper invocation into an actionable Dependabot
      # error. Known auth and plugin-resolution failures are mapped to their specific
      # error types, and genuine Maven diagnostics are surfaced via MisconfiguredTooling.
      # `run_shell_command` also reports inactivity timeouts and a missing `mvn`
      # executable as HelperSubprocessFailed; those carry no Maven `[ERROR]` markers, so
      # we re-raise the original error and let it follow normal unknown-error routing
      # instead of mislabelling infrastructure/runtime failures as tooling misconfigurations.
      sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.noreturn) }
      def self.handle_wrapper_error(error)
        # Strip ANSI color codes up front so classification and the surfaced summary see
        # plain text even when Maven is configured to emit colored output.
        output = error.message.gsub(ANSI_ESCAPE_REGEX, "")

        if (match = output.match(TRANSFER_FAILURE_REGEX)) &&
           (match[:status_code] == "403" || match[:status_code] == "401")
          raise Dependabot::PrivateSourceAuthenticationFailure, match[:repository_url]
        end

        if output.match?(WRAPPER_PLUGIN_UNRESOLVED_REGEX)
          raise Dependabot::DependencyFileNotResolvable, "Could not resolve the Maven Wrapper plugin."
        end

        # Only reclassify when Maven emitted its own `[ERROR]` diagnostics. Otherwise the
        # failure is not a Maven misconfiguration (e.g. timeout or missing executable), so
        # re-raise the original error; its full output is already in the job log.
        summary = mvn_error_summary(output)
        raise error unless summary

        raise Dependabot::MisconfiguredTooling.new("Maven Wrapper", summary)
      end

      # Extracts Maven's own `[ERROR]` lines from the combined tool output so that raised
      # errors surface the relevant failure reason without leaking unrelated build noise or
      # arbitrary subprocess output (which may contain sensitive file contents or paths) into
      # the reported error. Returns nil when Maven produced no `[ERROR]` diagnostics, and caps
      # the length to keep error payloads reasonable.
      sig { params(output: String).returns(T.nilable(String)) }
      def self.mvn_error_summary(output)
        error_lines = output.lines.map(&:chomp).select { |line| line.include?("[ERROR]") }
        return nil if error_lines.empty?

        summary = error_lines.join("\n")
        summary.length > MAX_ERROR_SUMMARY_LENGTH ? "#{summary[0, MAX_ERROR_SUMMARY_LENGTH]}..." : summary
      end
    end
  end
end
