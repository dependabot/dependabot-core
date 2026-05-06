# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/go_modules/go_work_parser"

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
        version = go_version_from_file(go_mod) ||
                  go_version_from_file(go_work) ||
                  all_workspace_go_mods.filter_map { |f| go_version_from_file(f) }.first ||
                  "unknown"

        {
          package_managers: {
            "gomod" => version
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        SharedHelpers.in_a_temporary_repo_directory(directory, clone_repo_contents) do
          fetched_files = collect_dependency_files
          validate_files!(fetched_files)
          fetched_files
        end
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def collect_dependency_files
        fetched_files = T.let([], T::Array[DependencyFile])

        if go_work
          fetched_files << T.must(go_work)
          fetched_files << T.must(go_work_sum) if go_work_sum
          fetched_files.concat(workspace_module_files)
        else
          fetched_files << T.must(go_mod) if go_mod
          fetched_files << T.must(go_sum) if go_sum
        end

        fetched_files << T.must(go_env) if go_env

        fetched_files
      end

      sig { params(files: T::Array[DependencyFile]).void }
      def validate_files!(files)
        return if files.any? { |f| f.name.end_with?("go.mod") }

        error_msg = go_work ? "No go.mod files found in workspace" : "No go.mod files found"
        raise Dependabot::DependencyFileNotFound.new(
          "go.mod",
          error_msg
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        @go_mod ||= T.let(fetch_file_if_present("go.mod"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_sum
        @go_sum ||= T.let(fetch_file_if_present("go.sum"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_work_sum
        @go_work_sum ||= T.let(fetch_file_if_present("go.work.sum"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_env
        return @go_env if defined?(@go_env)

        @go_env = T.let(fetch_support_file("go.env"), T.nilable(Dependabot::DependencyFile))
        @go_env
      end

      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T.nilable(String)) }
      def go_version_from_file(file)
        file&.content&.match(/^go\s+(\d+\.\d+)/)&.captures&.first
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def all_workspace_go_mods
        return [] unless go_work

        workspace_module_paths.filter_map do |module_path|
          name = module_path == "." ? "go.mod" : File.join(module_path, "go.mod")
          fetch_file_if_present(name)
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_work
        @go_work ||= T.let(fetch_file_if_present("go.work"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[String]) }
      def workspace_module_paths
        return [] unless go_work

        content = T.must(T.must(go_work).content)
        GoWorkParser.use_paths(content)
                    .select { |p| valid_module_path?(p) }
      end

      sig { params(path: String).returns(T::Boolean) }
      def valid_module_path?(path)
        return false if path.empty?
        return false if Pathname.new(path).absolute?
        return false if path.include?("\0")

        clean = Pathname.new(path).cleanpath.to_s
        return false if clean.start_with?("../")

        true
      end

      sig { returns(T::Array[DependencyFile]) }
      def workspace_module_files
        files = T.let([], T::Array[DependencyFile])

        workspace_module_paths.each do |module_path|
          mod_name = module_path == "." ? "go.mod" : File.join(module_path, "go.mod")
          mod_file = fetch_file_if_present(mod_name)
          next unless mod_file

          files << mod_file

          sum_name = module_path == "." ? "go.sum" : File.join(module_path, "go.sum")
          sum_file = fetch_file_if_present(sum_name)
          files << sum_file if sum_file
        end

        files
      end
    end
  end
end

Dependabot::FileFetchers
  .register("go_modules", Dependabot::GoModules::FileFetcher)
