# typed: strong
# frozen_string_literal: true

# See https://docs.npmjs.com/files/package.json for package.json format docs.

module Dependabot
  module Bun
    class FileParser < Dependabot::Javascript::FileParser
      extend T::Sig

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: PackageManager.new(detected_version:),
            language: Javascript::Language.new(detected_version:)
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(T.nilable(String)) }
      def detected_version
        Helpers.local_package_manager_version(Bun::PackageManager::NAME)
      end

      sig { override.returns(T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]) }
      def lockfiles
        {
          bun: bun_lock
        }
      end

      sig { override.returns(LockfileParser) }
      def lockfile_parser
        @lockfile_parser ||= T.let(LockfileParser.new(
                                     dependency_files: dependency_files
                                   ), T.nilable(LockfileParser))
      end

      sig { override.returns(T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]) }
      def registry_config_files
        {
          npmrc: npmrc
        }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def bun_lock
        @bun_lock ||= T.let(dependency_files.find do |f|
          f.name.end_with?(PackageManager::LOCKFILE_NAME)
        end, T.nilable(Dependabot::DependencyFile))
      end

      sig { override.returns(T.class_of(Version)) }
      def version_class
        Version
      end

      sig { override.returns(T.class_of(Requirement)) }
      def requirement_class
        Requirement
      end

      sig { override.void }
      def check_required_files; end
    end
  end
end

Dependabot::FileParsers
  .register(Dependabot::Bun::ECOSYSTEM, Dependabot::Bun::FileParser)
