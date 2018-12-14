# frozen_string_literal: true

require "dependabot/file_fetchers/java/gradle"

module Dependabot
  module FileFetchers
    module Java
      class Gradle
        class SettingsFileParser
          INCLUDE_ARGS_REGEX =
            /(?:^|\s)include(?:\(|\s)(\s*[^\s,\)]+(?:,\s*[^\s,\)]+)*)/.freeze

          def initialize(settings_file:)
            @settings_file = settings_file
          end

          def subproject_paths
            subprojects = []

            comment_free_content.scan(function_regex("include")) do
              args = Regexp.last_match.named_captures.fetch("args")
              args = args.split(",")
              args = args.map { |p| p.gsub(/["']/, "").strip }.compact
              subprojects += args
            end

            subprojects = subprojects.uniq

            subproject_dirs = subprojects.map do |proj|
              if comment_free_content.match?(project_dir_regex(proj))
                comment_free_content.match(project_dir_regex(proj)).
                  named_captures.fetch("path").sub(%r{^/}, "")
              else
                proj.tr(":", "/").sub(%r{^/}, "")
              end
            end

            subproject_dirs.uniq
          end

          private

          attr_reader :settings_file

          def comment_free_content
            settings_file.content.
              gsub(%r{(?<=^|\s)//.*$}, "\n").
              gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
          end

          def function_regex(function_name)
            /
              (?:^|\s)#{Regexp.quote(function_name)}(?:\(|\s)
              (?<args>\s*[^\s,\)]+(?:,\s*[^\s,\)]+)*)
            /mx
          end

          def project_dir_regex(proj)
            prefixed_proj = Regexp.quote(":#{proj.gsub(/^:/, '')}")
            /['"]#{prefixed_proj}['"].*dir\s*=.*['"](?<path>.*?)['"]/i
          end
        end
      end
    end
  end
end
