# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Nix
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/flake_nix_updater"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        flake_nix_content = T.must(flake_nix.content)

        if nixpkgs_branch_changed?
          flake_nix_content = FlakeNixUpdater.new(
            dependency: dependency,
            flake_nix_content: flake_nix_content
          ).updated_content

          updated_files << updated_file(file: flake_nix, content: flake_nix_content)
        end

        updated_lockfile_content = update_flake_lock(flake_nix_content)

        if updated_lockfile_content == flake_lock.content
          raise Dependabot::DependencyFileContentNotChanged,
                "Expected flake.lock to change for #{dependency.name}, but it didn't"
        end

        updated_files << updated_file(file: flake_lock, content: updated_lockfile_content)
        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        T.must(dependencies.first)
      end

      sig { returns(T::Boolean) }
      def nixpkgs_branch_changed?
        old_ref = dependency.previous_requirements&.first&.dig(:source, :ref)
        new_ref = dependency.requirements.first&.dig(:source, :ref)
        old_ref && new_ref && old_ref != new_ref
      end

      sig { params(flake_nix_content: String).returns(String) }
      def update_flake_lock(flake_nix_content)
        SharedHelpers.in_a_temporary_repo_directory(
          flake_lock.directory,
          repo_contents_path
        ) do
          File.write("flake.nix", flake_nix_content)
          File.write("flake.lock", T.must(flake_lock.content))

          SharedHelpers.run_shell_command(
            "nix flake update #{dependency.name}",
            fingerprint: "nix flake update <input_name>"
          )

          File.read("flake.lock")
        end
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
