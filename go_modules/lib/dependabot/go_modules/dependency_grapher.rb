# typed: strict
# frozen_string_literal: true

require "open3"
require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/go_modules/go_mod_manifest"
require "dependabot/go_modules/replace_stubber"
require "dependabot/manifest_sets/descriptor"
require "dependabot/shared_helpers"

module Dependabot
  module GoModules
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Used to capture output from `go mod graph`
      #
      # The parent and child are space-separated and we process one line at a time.
      #
      # Example output:
      #   github.com/dependabot/core-test rsc.io/sampler@v1.3.0
      #   rsc.io/sampler@v1.3.0 golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c
      #   <---parent--->        <----child------>
      #
      GO_MOD_GRAPH_LINE_REGEX = /^(?<parent>[^@\s]+)@?[^\s]*\s(?<child>[^@\s]+)/

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # This cannot realistically happen as the parser will throw a runtime error on init without a go_mod file,
        # but this will avoid surprises if anything changes.
        raise DependabotError, "No go.mod present in dependency files." unless go_mod

        T.must(go_mod)
      end

      sig { override.returns(T.nilable(String)) }
      def manifest_set_unresolvable_reason
        return Dependabot::ManifestSets::Descriptor::WORKSPACE if dependency_files.any? { |f| f.name == "go.work" }
        return Dependabot::ManifestSets::Descriptor::LOCAL_REPLACE if repository_local_replace?

        nil
      end

      private

      # A relative replace that resolves inside the repository makes the module's dependencies depend on files
      # beyond its own go.mod. Targets outside the repository are stubbed out by the parser and read nothing.
      sig { returns(T::Boolean) }
      def repository_local_replace?
        repo_contents_path = file_parser.repo_contents_path
        return false if repo_contents_path.nil? || go_mod.nil?

        manifest = go_mod_manifest
        stubbed = ReplaceStubber.new(repo_contents_path).stub_paths(manifest, go_mod&.directory)
        manifest.replacements.any? do |replacement|
          path = replacement.new.path
          path.start_with?("./", "../") && !stubbed.key?(path)
        end
      end

      sig { returns(GoModManifest) }
      def go_mod_manifest
        file = T.must(go_mod)
        stdout = SharedHelpers.in_a_temporary_directory do
          File.write("go.mod", file.content)
          out, stderr, status = Open3.capture3("go mod edit -json")
          raise Dependabot::DependencyFileNotParseable.new(file.path, stderr.strip) unless status.success?

          out
        end
        GoModManifest.from_json(stdout, file_path: file.path)
      end

      # go.sum only verifies checksums and go.env only configures module fetching, so go.mod alone determines
      # the resolved dependencies.
      sig { override.params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def manifest_set_input_file?(file)
        file.name == "go.mod"
      end

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        # go mod graph returns all dependencies it finds, even if it has been pruned. So filter those out.
        dependency_names = @dependencies.map(&:name)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_names.include?(child) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        return @go_mod if defined?(@go_mod)

        @go_mod = T.let(
          dependency_files.find { |f| f.name == "go.mod" },
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

      sig { returns(T::Hash[String, T.untyped]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def fetch_package_relationships
        T.cast(
          file_parser,
          Dependabot::GoModules::FileParser
        ).run_in_parsed_context("go mod graph").lines.each_with_object({}) do |line, rels|
          match = line.match(GO_MOD_GRAPH_LINE_REGEX)
          unless match
            Dependabot.logger.warn("Unexpected output from 'go mod graph': 'line'")
            next
          end

          rels[match[:parent]] ||= []
          rels[match[:parent]] << match[:child]
        end
      rescue Dependabot::DependencyFileNotParseable => e
        # Attempt to recategorise the error as related to repo resolvability
        repo_error_regex = FileUpdater::GoModUpdater::REPO_RESOLVABILITY_ERROR_REGEXES.find { |r| e.message =~ r }
        ResolvabilityErrors.handle(e.message) if repo_error_regex

        # Re-raise the original error if it isn't a resolvability problem.
        raise e
      end
    end
  end
end

Dependabot::DependencyGraphers.register("go_modules", Dependabot::GoModules::DependencyGrapher)
