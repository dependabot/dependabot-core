# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_fetcher"

module Dependabot
  module Gradle
    class FileFetcher
      class SettingsFileParser
        extend T::Sig

        sig { params(settings_file: Dependabot::DependencyFile).void }
        def initialize(settings_file:)
          @settings_file = settings_file
        end

        sig { returns(T::Array[String]) }
        def included_build_paths
          paths = []
          comment_free_content&.scan(function_regex("includeBuild")) do
            arg = T.must(Regexp.last_match).named_captures.fetch("args")
            paths << T.must(arg).gsub(/["']/, "").strip
          end
          paths.uniq
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def subproject_paths
          subprojects = T.let([], T::Array[String])

          comment_free_content&.scan(function_regex("include")) do
            args = T.must(Regexp.last_match).named_captures.fetch("args")
            args = T.must(args).split(",")
            args = args.filter_map { |p| p.gsub(/["']/, "").strip }
            subprojects += args
          end

          subprojects = subprojects.uniq

          subproject_dirs = subprojects.map do |proj|
            if comment_free_content&.match?(project_dir_regex(proj))
              comment_free_content&.match(project_dir_regex(proj))
                                  &.named_captures&.fetch("path")&.sub(%r{^/}, "")
            else
              proj.tr(":", "/").sub(%r{^/}, "")
            end
          end

          subproject_dirs.uniq
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :settings_file

        sig { returns(T.nilable(String)) }
        def comment_free_content
          settings_file.content
                       &.gsub(%r{(?<=^|\s)//.*$}, "\n")
                       &.gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
        end

        sig { params(function_name: T.any(String, Symbol)).returns(Regexp) }
        def function_regex(function_name)
          /
            (?:^|\s)#{Regexp.quote(function_name)}(?:\s*\(|\s)
            (?<args>\s*[^\s,\)]+(?:,\s*[^\s,\)]+)*)
          /mx
        end

        sig { params(proj: String).returns(Regexp) }
        def project_dir_regex(proj)
          prefixed_proj = Regexp.quote(":#{proj.gsub(/^:/, '')}")
          /['"]#{prefixed_proj}['"].*dir\s*=.*['"](?<path>.*?)['"]/i
        end
      end
    end
  end
end
