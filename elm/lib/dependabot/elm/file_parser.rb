# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/elm/requirement"
require "dependabot/elm/language"
require "dependabot/elm/package_manager"

module Dependabot
  module Elm
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_TYPES = T.let(%w(dependencies test-dependencies).freeze, T::Array[String])
      MANIFEST_FILE = T.let("elm.json", String)
      ELM_VERSION_KEY = T.let("elm-version", String)
      ECOSYSTEM = T.let("elm", String)
      DEFAULT_ELM_VERSION = T.let("0.19.1", String)

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_set += elm_json_dependencies if elm_json

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
        @package_manager ||= T.let(
          PackageManager.new(elm_version || DEFAULT_ELM_VERSION, elm_requirement),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          Language.new(elm_version || DEFAULT_ELM_VERSION, elm_requirement),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(T.nilable(Dependabot::Elm::Requirement)) }
      def elm_requirement
        @elm_requirement ||= T.let(
          extract_version_requirement(ELM_VERSION_KEY),
          T.nilable(Dependabot::Elm::Requirement)
        )
      end

      sig { returns(T.nilable(String)) }
      def elm_version
        content = extract_version(ELM_VERSION_KEY)
        return unless content

        @elm_version ||= T.let(content, T.nilable(String))
      end

      sig { params(field: String).returns(T.nilable(Dependabot::Elm::Requirement)) }
      def extract_version_requirement(field)
        content = extract_version_content(field)
        return unless content

        Dependabot::Elm::Requirement.new(content)
      end

      sig { params(field: String).returns(T.nilable(String)) }
      def extract_version(field)
        version_content = extract_version_content(field)
        return nil unless version_content

        version_match = version_content.match(/(\d+\.\d+\.\d+)/)
        version_match ? version_match[1] : nil
      end

      sig { params(field: String).returns(T.nilable(String)) }
      def extract_version_content(field)
        parsed_version = parsed_elm_json.fetch(field, nil)
        return nil if parsed_version.nil?
        return nil unless parsed_version.is_a?(String)
        return nil if parsed_version.empty?

        parsed_version
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def elm_json_dependencies
        dependency_set = DependencySet.new

        DEPENDENCY_TYPES.each do |dep_type|
          if repo_type == "application"
            dependencies_hash = T.cast(parsed_elm_json.fetch(dep_type, {}),
                                       T::Hash[String, T::Hash[String, String]])
            dependencies_hash.fetch("direct", {}).each do |name, req|
              dependency_set << build_elm_json_dependency(
                name: name, group: dep_type, requirement: req, direct: true
              )
            end
            dependencies_hash.fetch("indirect", {}).each do |name, req|
              dependency_set << build_elm_json_dependency(
                name: name, group: dep_type, requirement: req, direct: false
              )
            end
          elsif repo_type == "package"
            T.cast(parsed_elm_json.fetch(dep_type, {}), T::Hash[String, String]).each do |name, req|
              dependency_set << build_elm_json_dependency(
                name: name, group: dep_type, requirement: req, direct: true
              )
            end
          else
            raise "Unexpected repo type for Elm repo: #{repo_type}"
          end
        end

        dependency_set
      end

      sig do
        params(
          name: String,
          group: String,
          requirement: String,
          direct: T::Boolean
        ).returns(Dependabot::Dependency)
      end
      def build_elm_json_dependency(name:, group:, requirement:, direct:)
        requirements = [{
          requirement: requirement,
          groups: [group],
          source: nil,
          file: MANIFEST_FILE
        }]

        Dependency.new(
          name: name,
          version: version_for(requirement)&.to_s,
          requirements: direct ? requirements : [],
          package_manager: "elm"
        )
      end

      sig { returns(String) }
      def repo_type
        parsed_elm_json.fetch("type")
      end

      sig { override.void }
      def check_required_files
        return if elm_json

        raise "No #{MANIFEST_FILE}!"
      end

      sig do
        params(
          version_requirement: T.nilable(T.any(String, T::Array[T.nilable(String)]))
        ).returns(T.nilable(Gem::Version))
      end
      def version_for(version_requirement)
        req = Dependabot::Elm::Requirement.new(version_requirement)

        return unless req.exact?

        req.requirements.first.last
      end

      sig { returns(T.untyped) }
      def parsed_elm_json
        @parsed_elm_json ||= T.let(JSON.parse(T.must(T.must(elm_json).content)), T.untyped)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, elm_json&.path || MANIFEST_FILE
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def elm_json
        @elm_json ||= T.let(
          get_original_file(MANIFEST_FILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("elm", Dependabot::Elm::FileParser)
