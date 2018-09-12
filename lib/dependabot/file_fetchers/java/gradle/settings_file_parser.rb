# frozen_string_literal: true

require "dependabot/file_fetchers/java/gradle"

module Dependabot
  module FileFetchers
    module Java
      class Gradle
        class SettingsFileParser
          INCLUDE_ARGS_REGEX =
            /(?:^|\s)include(?:\(|\s)(\s*[^\s,\)]+(?:,\s*[^\s,\)]+)*)/

          def initialize(settings_file:)
            @settings_file = settings_file
          end

          def subproject_paths
            subproject_paths = []

            settings_file.content.scan(function_regex("include")) do
              args = Regexp.last_match.named_captures.fetch("args")
              args = args.split(",")
              args = args.map { |p| p.gsub(/["']/, "").strip }.compact
              args = args.map { |p| p.tr(":", "/").sub(%r{^/}, "") }
              subproject_paths += args
            end

            subproject_paths.uniq
          end

          private

          attr_reader :settings_file

          def function_regex(function_name)
            /
              (?:^|\s)#{Regexp.quote(function_name)}(?:\(|\s)
              (?<args>\s*[^\s,\)]+(?:,\s*[^\s,\)]+)*)
            /mx
          end
        end
      end
    end
  end
end
