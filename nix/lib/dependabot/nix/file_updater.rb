# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/nix/flake_nix_parser"
require "dependabot/nix/lockfile"

module Dependabot
  module Nix
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/flake_ref_builder"

      # Nix's CLI restricts flake input attribute path elements to this regex.
      # see `flakeIdRegex` in nix/src/libflake/include/nix/flake/flakeref.hh
      FLAKE_ID_REGEX = /\A[a-zA-Z][a-zA-Z0-9_-]*\z/

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        updated_flake_nix_content = update_flake_nix
        updated_files << updated_file(file: flake_nix, content: updated_flake_nix_content) if updated_flake_nix_content

        updated_lockfile_content = update_flake_lock(updated_flake_nix_content)
        validate_updated_revision(updated_lockfile_content)

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

        updated_content = FlakeNixParser.update_input_ref(T.must(flake_nix.content), dependency.name, new_ref)
        return updated_content if updated_content

        raise Dependabot::DependencyFileNotResolvable,
              "Cannot update the ref for flake input '#{dependency.name}' in flake.nix"
      end

      sig { params(updated_nix_content: T.nilable(String)).returns(String) }
      def update_flake_lock(updated_nix_content)
        lockfile = Lockfile.new(T.must(flake_lock.content))
        input_path = validated_input_path(lockfile)

        SharedHelpers.in_a_temporary_repo_directory(
          flake_lock.directory,
          repo_contents_path
        ) do
          File.write("flake.nix", updated_nix_content || T.must(flake_nix.content))
          File.write("flake.lock", T.must(flake_lock.content))

          SharedHelpers.run_shell_command(
            update_command(lockfile, input_path),
            fingerprint: command_fingerprint
          )

          File.read("flake.lock")
        end
      end

      sig { params(lockfile: Lockfile, input_path: String).returns(SharedHelpers::Command) }
      def update_command(lockfile, input_path)
        if git_dependency?
          source = updated_git_source(lockfile)
          revision = dependency.version
          unless source && revision
            raise Dependabot::DependencyFileNotResolvable,
                  "Cannot update flake input '#{dependency.name}' because its source metadata " \
                  "or target revision is missing"
          end

          exact_ref = build_exact_flake_ref(source, revision)
          # `nix flake lock` writes the override but keeps the input's original branch or tag.
          ["nix", "flake", "lock", "--override-input", input_path, exact_ref]
        elsif tarball_dependency?
          ["nix", "flake", "update", input_path]
        else
          raise Dependabot::DependencyFileNotResolvable,
                "Cannot update flake input '#{dependency.name}' because its dependency source type is not supported"
        end
      end

      sig { params(lockfile: Lockfile).returns(T.nilable(T::Hash[String, Object])) }
      def updated_git_source(lockfile)
        source = lockfile.original_source(dependency.name)
        return unless source

        ref = new_source_ref
        ref ? source.merge("ref" => ref) : source
      end

      sig { returns(String) }
      def command_fingerprint
        if git_dependency?
          "nix flake lock --override-input <input_path> <flake_ref>"
        else
          "nix flake update <input_name>"
        end
      end

      sig { params(source: T::Hash[String, Object], revision: String).returns(String) }
      def build_exact_flake_ref(source, revision)
        FlakeRefBuilder.new(source: source, revision: revision).to_s
      rescue ArgumentError, URI::InvalidURIError => e
        raise Dependabot::DependencyFileNotResolvable,
              "Cannot update flake input '#{dependency.name}': #{e.message}"
      end

      sig { params(lockfile: Lockfile).returns(String) }
      def validated_input_path(lockfile)
        path = lockfile.input_path(dependency.name)
        unless path&.all? { |segment| segment.match?(FLAKE_ID_REGEX) }
          raise Dependabot::DependencyFileNotResolvable,
                "Cannot update flake input '#{dependency.name}': each Nix input path segment must match " \
                "[a-zA-Z][a-zA-Z0-9_-]*"
        end

        path.join("/")
      end

      sig { params(content: String).void }
      def validate_updated_revision(content)
        expected_revision = dependency.version
        actual_revision = Lockfile.new(content).locked_revision(dependency.name)
        return if expected_revision && actual_revision == expected_revision

        raise Dependabot::DependencyFileNotResolvable,
              "Expected flake input '#{dependency.name}' to lock revision " \
              "#{expected_revision.inspect}, but Nix generated #{actual_revision.inspect}"
      rescue JSON::ParserError => e
        raise Dependabot::DependencyFileNotResolvable,
              "Nix generated an invalid flake.lock for '#{dependency.name}': #{e.message}"
      end

      sig { returns(T::Boolean) }
      def git_dependency?
        dependency.requirements.first&.source_string("type") == "git"
      end

      sig { returns(T::Boolean) }
      def tarball_dependency?
        dependency.requirements.first&.source_string("type") == "tarball"
      end

      sig { returns(T.nilable(String)) }
      def new_source_ref
        dependency.requirements.first&.source_string("ref")
      end

      sig { returns(T.nilable(String)) }
      def old_source_ref
        dependency.previous_requirements&.first&.source_string("ref")
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
