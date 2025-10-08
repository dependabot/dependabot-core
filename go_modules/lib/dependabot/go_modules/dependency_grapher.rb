# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"

module Dependabot
  module GoModules
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      GO_MOD_GRAPH_LINE_REGEX = /^(?<parent>[^@\s]+)@?[^\s]*\s+(?<child>[^@\s]+)/

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # This cannot realistically happen as the parser will throw a runtime error on init without a go_mod file,
        # but this will avoid surprises if anything changes.
        raise DependabotError, "No go.mod present in dependency files." unless go_mod

        T.must(go_mod)
      end

      private

      # TODO: Build subdependency in this class and assign here -or- assign metadata in the parser
      #
      # We can do whichever makes most sense on a case-by-case basis, for Go the trade off on
      # doing this in the parser shouldn't add a huge overhead.
      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        package_relationships.fetch(dependency.name, [])
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        return @go_mod if defined?(@go_mod)

        @go_mod = T.let(
          dependency_files.find { |f| f.name = "go.mod" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      # In Go, the `v` is considered a canonical part of the version and omitting it can make
      # comparisons tricky
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def purl_version_for(dependency)
        return "" unless dependency.version

        "@v#{dependency.version}"
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "golang"
      end

      # TODO: Expose a 'run this' method on the parser instead of copy-pasting this
      sig { returns(T::Hash[String, T.untyped]) }
      def package_relationships
        @package_relationships ||= T.let(
          SharedHelpers.in_a_temporary_directory do |path|
            # Create a fake empty module for each local module so that
            # `go mod edit` works, even if some modules have been `replace`d with
            # a local module that we don't have access to.
            local_replacements.each do |_, stub_path|
              FileUtils.mkdir_p(stub_path)
              FileUtils.touch(File.join(stub_path, "go.mod"))
            end

            File.write("go.mod", go_mod_content)

            command = "go mod graph"

            stdout, stderr, status = Open3.capture3(command)
            handle_parser_error(path, stderr) unless status.success?

            stdout.lines.each_with_object({}) do |line, rels|
              match = line.match(GO_MOD_GRAPH_LINE_REGEX)
              next unless match # TODO: Warn if we get a weird line?

              rels[match[:parent]] ||= []
              rels[match[:parent]] << match[:child]
            end
          end,
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T::Hash[String, String]) }
      def local_replacements
        T.cast(file_parser, Dependabot::GoModules::FileParser).local_replacements
      end

      sig { returns(T.nilable(String)) }
      def go_mod_content
        T.cast(file_parser, Dependabot::GoModules::FileParser).go_mod_content
      end

      sig { params(path: T.any(Pathname, String), stderr: String).returns(T.noreturn) }
      def handle_parser_error(path, stderr)
        msg = stderr.gsub(path.to_s, "").strip
        raise Dependabot::DependencyFileNotParseable.new(T.must(go_mod).path, msg)
      end
    end
  end
end

Dependabot::DependencyGraphers.register("go_modules", Dependabot::GoModules::DependencyGrapher)
