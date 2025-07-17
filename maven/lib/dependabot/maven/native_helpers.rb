# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"

module Dependabot
  module Maven
    module NativeHelpers
      extend T::Sig
      # Latest version of the plugin can be found here - https://mvnrepository.com/artifact/org.apache.maven.plugins/maven-dependency-plugin
      DEPENDENCY_PLUGIN_VERSION = "3.8.1"

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
        )) && (match[:status_code] == ("403") || match[:status_code] == ("401"))
          raise Dependabot::PrivateSourceAuthenticationFailure, match[:repository_url]
        end

        raise DependabotError, "mvn CLI failed with an unhandled error"
      end
    end
  end
end
