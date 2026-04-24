# typed: strict
# frozen_string_literal: true

require "fileutils"
require "open3"
require "shellwords"
require "uri"
require "sorbet-runtime"
require "nokogiri"
require "dependabot/shared_helpers"

module Dependabot
  module Maven
    module NativeHelpers
      extend T::Sig

      pom_path = File.join(__dir__, "pom.xml")

      dependency_plugin_version, wrapper_plugin_version = File.open(pom_path) do |f|
        doc = Nokogiri::XML(f)
        [
          doc.at_xpath("//project/properties/maven-dependency-plugin.version")&.text,
          doc.at_xpath("//project/properties/maven-wrapper-plugin.version")&.text
        ]
      end

      DEPENDENCY_PLUGIN_VERSION = T.let(dependency_plugin_version, T.nilable(String))

      # Fallback wrapper plugin version for projects where wrapperVersion cannot
      # be determined: Maven Wrapper 3.3.0 has no machine-readable version in the
      # properties file (wrapperUrl removed in MWRAPPER-120, wrapperVersion not
      # added until 3.3.1 via MWRAPPER-134), and 3.3.3 accidentally omitted it.
      # Read from pom.xml and kept current by Dependabot.
      WRAPPER_PLUGIN_DEFAULT_VERSION = T.let(wrapper_plugin_version, T.nilable(String))

      sig do
        params(file_name: String).void
      end
      def self.run_mvn_dependency_tree_plugin(file_name)
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
        if (match = output.match(
          %r{Could not transfer artifact (?<artifact>[^ ]+) from/to (?<repository_name>[^ ]+) \((?<repository_url>[^ ]+)\): status code: (?<status_code>[0-9]+)} # rubocop:disable Layout/LineLength
        )) && (match[:status_code] == "403" || match[:status_code] == "401")
          raise Dependabot::PrivateSourceAuthenticationFailure, match[:repository_url]
        end

        raise DependabotError, "mvn CLI failed with an unhandled error"
      end

      # Runs the Maven Wrapper plugin in the given directory to regenerate
      # wrapper scripts and artifacts for the specified Maven distribution version.
      #
      # Binary selection strategy:
      #   1. ./mvnw (after chmod +x) — uses the project's own wrapper, which
      #      ensures the same JVM flags and settings.xml as the project uses.
      #   2. Falls back to system `mvn` if the local script is absent or fails.
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
          dir: String,
          env: T::Hash[String, String],
          extra_args: T::Array[String]
        ).void
      end
      def self.run_mvnw_wrapper(version:, wrapper_plugin_version:, dir:, env:, extra_args: [])
        local_script = File.join(dir, "mvnw")
        has_local_script = File.exist?(local_script)

        # Ensure the Unix wrapper script is executable before invoking it.
        # File-writing in a temporary directory does not preserve the permissions,
        # so ./mvnw would fail with "Permission denied" without this step.
        FileUtils.chmod("+x", local_script) if has_local_script

        # Use the fully-qualified plugin goal so the exact plugin version is
        # invoked regardless of the project's plugin group configuration.
        plugin_goal = "org.apache.maven.plugins:maven-wrapper-plugin:" \
                      "#{wrapper_plugin_version}:wrapper"

        standard_args = [
          plugin_goal,
          "-Dmaven=#{version}",
          "--no-transfer-progress"
        ] + extra_args

        # Prefer the project's own wrapper script. If it fails, fall back to system mvn.
        if has_local_script
          begin
            cmd = Shellwords.join(["./mvnw"] + standard_args)
            SharedHelpers.run_shell_command(cmd, env: env)
            return
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
            Dependabot.logger.warn(
              "mvnw #{plugin_goal} failed (#{e.message}), " \
              "retrying with system mvn"
            )
          end
        end

        # System mvn fallback. Maven is pre-installed in the container
        cmd = Shellwords.join(["mvn"] + standard_args)
        SharedHelpers.run_shell_command(cmd, env: env)
      end
    end
  end
end
