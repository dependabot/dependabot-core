# typed: true
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
      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_TYPES = %w(dependencies test-dependencies).freeze

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

      # Extracts the version content (e.g., "1.9.1" or "<= 1.9.1") and parses it to return only the version part
      sig { params(field: String).returns(T.nilable(String)) }
      def extract_version(field)
        version_content = extract_version_content(field)
        return nil unless version_content

        # Extract only the version part (e.g., "1.9.1") from the string
        version_match = version_content.match(/(\d+\.\d+\.\d+)/)
        version_match ? version_match[1] : nil
      end

      sig { params(field: String).returns(T.nilable(String)) }
      def extract_version_content(field)
        parsed_version = parsed_elm_json.fetch(field, nil)

        return if parsed_version.nil? || parsed_version.empty?

        parsed_version
      end

      # For docs on elm.json, see:
      # https://github.com/elm/compiler/blob/master/docs/elm.json/application.md
      # https://github.com/elm/compiler/blob/master/docs/elm.json/package.md
      def elm_json_dependencies
        dependency_set = DependencySet.new

        DEPENDENCY_TYPES.each do |dep_type|
          if repo_type == "application"
            dependencies_hash = parsed_elm_json.fetch(dep_type, {})
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
            parsed_elm_json.fetch(dep_type, {}).each do |name, req|
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

      def version_for(version_requirement)
        req = Dependabot::Elm::Requirement.new(version_requirement)

        return unless req.exact?

        req.requirements.first.last
      end

      def parsed_elm_json
        @parsed_elm_json ||= JSON.parse(elm_json.content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, elm_json&.path || MANIFEST_FILE
      end

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
