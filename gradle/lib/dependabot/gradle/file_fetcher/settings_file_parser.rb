# typed: strong
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

        sig { returns(T::Array[String]) }
        def version_catalog_paths
          paths = []
          return paths unless comment_free_content

          match_data = T.must(comment_free_content).match(version_catalogs_block_regex)
          return paths unless match_data

          catalogs_block = match_data.named_captures["catalogs_block"]
          return paths unless catalogs_block

          catalogs_block.scan(catalog_file_path_regex) do
            paths << T.must(T.must(Regexp.last_match).named_captures["path"])
          end

          paths.uniq
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def subproject_paths
          subprojects = T.let([], T::Array[String])
          process_include_functions(subprojects)
          subprojects.uniq.map { |name| process_subproject_name(name) }
        end

        private

        sig { params(subprojects: T::Array[String]).void }
        def process_include_functions(subprojects)
          comment_free_content&.scan(function_regex("include")) do
            args = T.must(Regexp.last_match).named_captures.fetch("args")
            args = T.must(args).split(",")
            args = args.filter_map { |p| p.gsub(/["']/, "").strip }
            subprojects.concat(args)
          end
        end

        sig { params(proj: String).returns(T.nilable(String)) }
        def process_subproject_name(proj)
          if comment_free_content&.match?(project_dir_regex(proj))
            comment_free_content&.match(project_dir_regex(proj))
                                &.named_captures&.fetch("path")&.sub(%r{^/}, "")
          else
            proj.tr(":", "/").sub(%r{^/}, "")
          end
        end

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

        sig { returns(Regexp) }
        def version_catalogs_block_regex
          /dependencyResolutionManagement\s*\{.*?versionCatalogs\s*\{(?<catalogs_block>.*)\}/m
        end

        sig { returns(Regexp) }
        def catalog_file_path_regex
          /from\s*\(?\s*files\s*\(?\s*['"](?<path>[^'"]+)['"]\s*\)?\s*\)?/
        end
      end
    end
  end
end
