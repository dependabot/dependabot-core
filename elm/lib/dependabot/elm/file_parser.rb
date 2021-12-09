# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/elm/requirement"

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

      private

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
          file: "elm.json"
        }]

        Dependency.new(
          name: name,
          version: version_for(requirement)&.to_s,
          requirements: direct ? requirements : [],
          package_manager: "elm"
        )
      end

      def repo_type
        parsed_elm_json.fetch("type")
      end

      def check_required_files
        return if elm_json

        raise "No elm.json"
      end

      def version_for(version_requirement)
        req = Dependabot::Elm::Requirement.new(version_requirement)

        return unless req.exact?

        req.requirements.first.last
      end

      def parsed_elm_json
        @parsed_elm_json ||= JSON.parse(elm_json.content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, elm_json.path
      end

      def elm_json
        @elm_json ||= get_original_file("elm.json")
      end
    end
  end
end

Dependabot::FileParsers.register("elm", Dependabot::Elm::FileParser)
