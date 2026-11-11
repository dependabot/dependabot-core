# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/ecosystem"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/clojure/constants"
require "dependabot/clojure/language"
require "dependabot/clojure/native_helpers"
require "dependabot/clojure/package_manager"

module Dependabot
  module Clojure
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      CLOJURE_DEPENDENCY_NAME = "org.clojure:clojure"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        manifest_files.each do |file|
          tracked_declarations(file).each do |declaration|
            dependency_set << build_dependency(file, declaration)
          end
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: Language.new(clojure_version)
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      # A profile or alias that declares another version than the top-level one
      # is a deliberate pin, such as a profile that tests an older Clojure
      # release, so it isn't tracked.
      sig { params(file: Dependabot::DependencyFile).returns(T::Array[NativeHelpers::Declaration]) }
      def tracked_declarations(file)
        declarations = NativeHelpers.parse(file).declarations
        main_versions = declarations.select { |dep| dep.groups.include?(MAIN_GROUP) }
                                    .to_h { |dep| [dep.name, dep.version] }

        declarations.select do |dep|
          dep.groups.include?(MAIN_GROUP) || main_versions.fetch(dep.name, dep.version) == dep.version
        end
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          declaration: NativeHelpers::Declaration
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(file, declaration)
        metadata = declaration.classifier ? { classifier: declaration.classifier } : nil

        Dependency.new(
          name: declaration.name,
          version: declaration.version,
          requirements: [{
            requirement: declaration.version,
            file: file.name,
            groups: declaration.groups,
            source: nil,
            metadata: metadata
          }],
          package_manager: ECOSYSTEM
        )
      end

      # The project files don't say which version of Leiningen or the Clojure
      # CLI is used, so only the name is reported.
      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        PackageManager.new(lein_file ? LEIN_PACKAGE_MANAGER : DEPS_PACKAGE_MANAGER)
      end

      sig { returns(T.nilable(String)) }
      def clojure_version
        manifest_files.each do |file|
          declaration = NativeHelpers.parse(file).declarations.find do |dep|
            dep.name == CLOJURE_DEPENDENCY_NAME && dep.groups.include?(MAIN_GROUP)
          end
          return declaration.version if declaration
        end
        nil
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        [lein_file, deps_file].compact
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lein_file
        get_original_file(LEIN_FILE_NAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def deps_file
        get_original_file(DEPS_FILE_NAME)
      end

      sig { override.void }
      def check_required_files
        return if lein_file || deps_file

        raise "No #{LEIN_FILE_NAME} or #{DEPS_FILE_NAME}!"
      end
    end
  end
end

Dependabot::FileParsers.register(Dependabot::Clojure::ECOSYSTEM, Dependabot::Clojure::FileParser)
