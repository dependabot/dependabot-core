# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/nix/flake_nix_parser"

module Dependabot
  module Nix
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        updated_flake_nix_content = update_flake_nix
        updated_files << updated_file(file: flake_nix, content: updated_flake_nix_content) if updated_flake_nix_content

        updated_lockfile_content = update_flake_lock(updated_flake_nix_content)

        if updated_lockfile_content == flake_lock.content
          raise Dependabot::DependencyFileContentNotChanged,
                "Expected flake.lock to change for #{dependency_names.join(', ')}, but it didn't"
        end

        updated_files << updated_file(file: flake_lock, content: updated_lockfile_content)
        updated_files
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      def unique_dependencies
        dependencies.uniq(&:name)
      end

      # Returns updated flake.nix content if the ref changed, nil otherwise.
      sig { returns(T.nilable(String)) }
      def update_flake_nix
        updated_content = T.let(T.must(flake_nix.content), String)

        unique_dependencies.each do |dependency|
          new_ref = new_source_ref(dependency)
          next unless new_ref

          old_ref = old_source_ref(dependency)
          next unless old_ref
          next if old_ref == new_ref

          updated_input_content = FlakeNixParser.update_input_ref(updated_content, dependency.name, new_ref)
          updated_content = updated_input_content if updated_input_content
        end

        return if updated_content == flake_nix.content

        updated_content
      end

      sig { params(updated_nix_content: T.nilable(String)).returns(String) }
      def update_flake_lock(updated_nix_content)
        SharedHelpers.in_a_temporary_repo_directory(
          flake_lock.directory,
          repo_contents_path
        ) do
          File.write("flake.nix", updated_nix_content || T.must(flake_nix.content))
          File.write("flake.lock", T.must(flake_lock.content))

          SharedHelpers.run_shell_command(
            Shellwords.join(["nix", "flake", "update", *dependency_names]),
            fingerprint: "nix flake update <input_names>"
          )

          File.read("flake.lock")
        end
      end

      sig { returns(T::Array[String]) }
      def dependency_names
        unique_dependencies.map(&:name)
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def new_source_ref(dependency)
        dependency.requirements.first&.dig(:source, :ref)
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def old_source_ref(dependency)
        dependency.previous_requirements&.first&.dig(:source, :ref)
      end

      sig { override.void }
      def check_required_files
        %w(flake.nix flake.lock).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      sig { returns(Dependabot::DependencyFile) }
      def flake_lock
        @flake_lock ||=
          T.let(
            T.must(get_original_file("flake.lock")),
            T.nilable(Dependabot::DependencyFile)
          )
      end

      sig { returns(Dependabot::DependencyFile) }
      def flake_nix
        @flake_nix ||=
          T.let(
            T.must(get_original_file("flake.nix")),
            T.nilable(Dependabot::DependencyFile)
          )
      end
    end
  end
end

Dependabot::FileUpdaters.register("nix", Dependabot::Nix::FileUpdater)
