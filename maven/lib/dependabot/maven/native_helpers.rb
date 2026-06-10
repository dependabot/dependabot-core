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

      version = File.open(pom_path) do |f|
        doc = Nokogiri::XML(f)
        doc.at_xpath("//project/properties/maven-dependency-plugin.version")&.text
      end

      DEPENDENCY_PLUGIN_VERSION = T.let(version, T.nilable(String))

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
          extra_args: T::Array[String]
        ).void
      end
      def self.run_mvnw_wrapper(version:, wrapper_plugin_version:, env:, distribution_type:, extra_args: [])
        # Use the fully-qualified plugin goal so the exact plugin version is
        # invoked regardless of the project's plugin group configuration.
        plugin_goal = "org.apache.maven.plugins:maven-wrapper-plugin:" \
                      "#{wrapper_plugin_version}:wrapper"

        standard_args = [
          plugin_goal,
          "-Dmaven=#{version}",
          "-Dtype=#{distribution_type}",
          "--no-transfer-progress"
        ] + extra_args

        cmd = Shellwords.join(["mvn"] + standard_args)
        SharedHelpers.run_shell_command(cmd, env: env)
      end
    end
  end
end
