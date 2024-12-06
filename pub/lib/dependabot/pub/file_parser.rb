# typed: strict
# frozen_string_literal: true

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/dependency"
require "dependabot/pub/version"
require "dependabot/pub/helpers"
require "dependabot/pub/package_manager"
require "dependabot/pub/language"
require "sorbet-runtime"

module Dependabot
  module Pub
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      include Dependabot::Pub::Helpers

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        list.map do |d|
          dependency_set << parse_listed_dependency(d)
        end
        dependency_set.dependencies.sort_by(&:name)
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        detected_package_manager
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        Language.new(T.must(dart_raw_version))
      end

      sig { returns(T.nilable(String)) }
      def dart_raw_version
        version_info = SharedHelpers.run_shell_command("dart --version").split("version:")
                                    .last&.split&.first&.strip

        Dependabot.logger.info("Ecosystem #{ECOSYSTEM}, Info : #{version_info}")

        version_info
      rescue StandardError => e
        Dependabot.logger.error(e.message)
        nil
      end

      sig { returns(Ecosystem::VersionManager) }
      def detected_package_manager
        # pub package manager is shipped with Dart SDK and is no longer available
        # as separate project, So versioning is no longer relevant for pub package manager
        PubPackageManager.new(PubPackageManager::VERSION)
      end

      sig { override.void }
      def check_required_files
        raise "No pubspec.yaml!" unless get_original_file("pubspec.yaml")
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def list
        @list ||= T.let(dependency_services_list, T.nilable(T::Array[Dependabot::Dependency]))
      end
    end
  end
end

Dependabot::FileParsers.register("pub", Dependabot::Pub::FileParser)
