# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module GoModules
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("go.mod") || filenames.include?("go.work")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a go.mod or go.work."
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def ecosystem_versions
        {
          package_managers: {
            "gomod" => go_mod&.content&.match(/^go\s(\d+\.\d+)/)&.captures&.first || "unknown"
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # Ensure we always check out the full repo contents for go_module
        # updates.
        SharedHelpers.in_a_temporary_repo_directory(
          directory,
          clone_repo_contents
        ) do
          fetched_files = []

          # If go.work exists, fetch it and all workspace modules
          if go_work
            fetched_files << T.must(go_work)
            workspace_files = workspace_module_files

            # Ensure at least one workspace module was found
            raise Dependabot::DependencyFileNotFound.new(
              "go.mod",
              "go.work found but no workspace modules with go.mod files could be fetched"
            ) if workspace_files.empty?

            fetched_files.concat(workspace_files)

            # Also fetch root go.mod and go.sum if they exist (root might be included in workspace)
            fetched_files << go_mod if go_mod
            fetched_files << T.must(go_sum) if go_sum
          elsif go_mod
            # Fallback to single module mode
            fetched_files << go_mod
            fetched_files << T.must(go_sum) if go_sum
          end

          fetched_files << T.must(go_env) if go_env
          fetched_files
        end
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        @go_mod ||= T.let(fetch_file_if_present("go.mod"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_sum
        @go_sum ||= T.let(fetch_file_if_present("go.sum"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_env
        return @go_env if defined?(@go_env)

        @go_env = T.let(fetch_support_file("go.env"), T.nilable(Dependabot::DependencyFile))
        @go_env
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_work
        @go_work ||= T.let(fetch_file_if_present("go.work"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[String]) }
      def workspace_module_paths
        return [] unless go_work

        # Parse go.work file to extract module paths
        content = T.must(T.must(go_work).content)
        paths = []

        # Match "use" directives in go.work
        # Format can be:
        #   1. use ./path/to/module (single line)
        #   2. use (
        #        ./path1
        #        ./path2
        #      )
        # Note: Files can contain both formats

        # Parse multi-line use blocks
        T.must(content).scan(/^use\s+\(([^)]+)\)/m).each do |block_match|
          block_match[0].scan(%r{^\s*\.?/?([\S]+)}).each do |path_match|
            paths << path_match[0]
          end
        end

        # Parse single-line use directives (not followed by opening paren)
        T.must(content).scan(/^use\s+(?!\()\.?\/?([\S]+)/m).each do |path_match|
          paths << path_match[0]
        end

        # Normalize and validate paths
        paths.map { |p| p.sub(%r{^\./}, "") }
             .select { |p| valid_workspace_path?(p) }
             .uniq
      end

      sig { params(path: String).returns(T::Boolean) }
      def valid_workspace_path?(path)
        # Reject absolute paths
        return false if Pathname.new(path).absolute?

        # Reject paths containing null bytes
        return false if path.include?("\0")

        # Clean and normalize the path
        clean_path = Pathname.new(path).cleanpath.to_s

        # Reject if the cleaned path tries to escape (starts with ../)
        return false if clean_path.start_with?("../")

        # Reject if the path is just "." or empty
        return false if clean_path == "." || clean_path.empty?

        # Additional safety: ensure the path doesn't contain suspicious patterns
        return false if path.include?("//") || path.include?("\\")

        true
      end

      sig { returns(T::Array[DependencyFile]) }
      def workspace_module_files
        files = []

        workspace_module_paths.each do |module_path|
          # module_path is already validated by valid_workspace_path?
          # but we double-check here for defense in depth
          next unless valid_workspace_path?(module_path)

          # Construct the full path for go.mod
          mod_path = File.join(module_path, "go.mod")
          sum_path = File.join(module_path, "go.sum")

          # Fetch go.mod for this module
          mod_file = fetch_file_if_present(mod_path)
          files << mod_file if mod_file

          # Fetch go.sum if it exists
          sum_file = fetch_file_if_present(sum_path)
          files << sum_file if sum_file
        end

        files
      end
    end
  end
end

Dependabot::FileFetchers
  .register("go_modules", Dependabot::GoModules::FileFetcher)
