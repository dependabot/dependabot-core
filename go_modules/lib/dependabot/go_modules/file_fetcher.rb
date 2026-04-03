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
        filenames.include?("go.mod")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a go.mod."
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
            fetched_files.concat(workspace_module_files)
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
        content = T.must(go_work).content
        paths = []

        # Match "use" directives in go.work
        # Format: use ./path/to/module or use ( ./path1 ./path2 )
        content.scan(/^use\s+\(([^)]+)\)/m).each do |block_match|
          # Multi-line use block
          block_match[0].scan(/^\s*\.?\/?([\S]+)/).each do |path_match|
            paths << path_match[0]
          end
        end

        # Single line use directives
        content.scan(/^use\s+\.?\/?(\S+)/).each do |path_match|
          paths << path_match[0] unless content =~ /^use\s+\(/
        end

        paths.uniq
      end

      sig { returns(T::Array[DependencyFile]) }
      def workspace_module_files
        files = []

        workspace_module_paths.each do |module_path|
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
