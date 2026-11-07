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
          content = settings_file.content
          return [] unless content

          masked = FileParser.mask_literals_and_comments(content, kotlin: settings_file.name.end_with?(".kts"))
          catalog_blocks = masked.to_enum(:scan, version_catalogs_block_regex).map do
            match = T.must(Regexp.last_match)
            match.begin(0)..(match.end(0) + closing_bracket_index(T.must(masked[match.end(0)..])))
          end

          paths = content.to_enum(:scan, catalog_file_path_regex).filter_map do
            match = T.must(Regexp.last_match)
            start = match.begin(0)
            next unless masked[start, 4] == "from" && catalog_blocks.any? { |block| block.cover?(start) }

            resolve_catalog_path(T.must(match[:path]))
          end
          paths.uniq
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def subproject_paths
          subprojects = T.let([], T::Array[String])
          process_include_functions(subprojects)
          subprojects.uniq.map { |name| process_subproject_name(name) }
        end

        # Returns a map of filesystem directory path => Gradle project name for all declared subprojects.
        # For example: { 'app' => ':app', 'subprojects/chrome-trace' => ':chrome-trace' }
        # This correctly handles custom projectDir mappings in settings files.
        sig { returns(T::Hash[String, String]) }
        def subproject_path_to_name_map
          subprojects = T.let([], T::Array[String])
          process_include_functions(subprojects)
          subprojects.uniq.each_with_object(T.let({}, T::Hash[String, String])) do |name, map|
            path = process_subproject_name(name)
            next unless path

            # Normalise name to Gradle colon-separated project path (e.g. ':app', ':sub:module')
            map[path] = ":#{name.sub(/^:/, '')}"
          end
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

        sig { params(path: String).returns(T.nilable(String)) }
        def resolve_catalog_path(path)
          resolved = path.sub(%r{\A\$(?:\{(?:rootDir|settingsDir)\}|rootDir|settingsDir)/}, "")
          resolved unless resolved.include?("$")
        end

        sig { params(string: String).returns(Integer) }
        def closing_bracket_index(string)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == "{"
            closes_required -= 1 if char == "}"
            return index if closes_required.zero?
          end

          0
        end

        sig { returns(Regexp) }
        def version_catalogs_block_regex
          /\bversionCatalogs\s*(?:\.\s*(?:create|register)\s*\([^)]*\)\s*)?\{/
        end

        sig { returns(Regexp) }
        def catalog_file_path_regex
          /
            \bfrom\s*\(?\s*files\s*\(?\s*
            (?:layout\s*\.\s*(?:rootDirectory|settingsDirectory)\s*\.\s*file\s*\(\s*)?
            (?<quote>["'])(?<path>[^"']+)\k<quote>
          /x
        end
      end
    end
  end
end
