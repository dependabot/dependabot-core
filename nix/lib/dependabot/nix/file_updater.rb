# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

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

      # Returns updated flake.nix content if the ref changed, nil otherwise.
      sig { returns(T.nilable(String)) }
      def update_flake_nix
        new_ref = new_source_ref
        return unless new_ref

        old_ref = old_source_ref
        return unless old_ref
        return if old_ref == new_ref

        FlakeNixParser.update_input_ref(T.must(flake_nix.content), dependency.name, new_ref)
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
            "nix flake update #{dependency.name}",
            env: nix_access_tokens_env,
            fingerprint: "nix flake update <input_name>"
          )

          File.read("flake.lock")
        end
      end

      # Builds NIX_CONFIG with access-tokens from git_source credentials so
      # nix flake update can authenticate against private repositories.
      # Uses NIX_CONFIG rather than --extra-access-tokens to keep tokens
      # out of the process command line.
      sig { returns(T::Hash[String, String]) }
      def nix_access_tokens_env
        host_token_pairs = credentials.filter_map do |credential|
          next unless credential["type"] == "git_source"

          host = credential["host"]
          password = credential["password"]
          next if host.to_s.empty? || password.to_s.empty?

          [host, password]
        end

        tokens = host_token_pairs.uniq(&:first).map { |host, password| "#{host}=#{password}" }

        return {} if tokens.empty?

        { "NIX_CONFIG" => "access-tokens = #{tokens.join(' ')}" }
      end

      sig { returns(T.nilable(String)) }
      def new_source_ref
        dependency.requirements.first&.dig(:source, :ref)
      end

      sig { returns(T.nilable(String)) }
      def old_source_ref
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
