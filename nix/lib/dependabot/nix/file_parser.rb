# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/nix/lockfile"
require "dependabot/nix/package_manager"

module Dependabot
  module Nix
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      SUPPORTED_LOCK_VERSION = 7

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        lockfile = Lockfile.from_file(flake_lock)

        lock_version = lockfile.version
        if lock_version != SUPPORTED_LOCK_VERSION
          Dependabot.logger.warn(
            "flake.lock version #{lock_version.inspect} differs from expected #{SUPPORTED_LOCK_VERSION}"
          )
        end

        lockfile.root_input_names.filter_map do |input_name|
          input = lockfile.dependency_input(input_name)
          next unless input

          build_dependency(input_name, input)
        end
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig do
        params(
          input_name: String,
          input: Lockfile::DependencyInput
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(input_name, input)
        Dependency.new(
          name: input_name,
          version: input.revision,
          package_manager: "nix",
          requirements: [{
            requirement: nil,
            file: "flake.lock",
            source: { type: input.type, url: input.url, branch: nil, ref: input.ref },
            groups: []
          }]
        )
      end

      sig { returns(Dependabot::DependencyFile) }
      def flake_lock
        @flake_lock ||=
          T.let(
            T.must(get_original_file("flake.lock")),
            T.nilable(Dependabot::DependencyFile)
          )
      end

      sig { override.void }
      def check_required_files
        %w(flake.nix flake.lock).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(nix_version)),
          T.nilable(Dependabot::Nix::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def nix_version
        @nix_version ||= T.let(
          begin
            version_output = SharedHelpers.run_shell_command("nix --version")
            version_output.match(/nix.*?(\d+\.\d+[\.\d]*)/)&.captures&.first || "0.0.0"
          rescue StandardError
            "0.0.0"
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("nix", Dependabot::Nix::FileParser)
