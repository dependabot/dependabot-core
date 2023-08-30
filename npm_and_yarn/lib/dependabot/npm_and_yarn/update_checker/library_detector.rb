# frozen_string_literal: true

require "excon"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class LibraryDetector
        def initialize(package_json_file:, credentials:, dependency_files:)
          @package_json_file = package_json_file
          @credentials = credentials
          @dependency_files = dependency_files
        end

        def library?
          return false unless package_json_may_be_for_library?

          npm_response_matches_package_json?
        end

        private

        attr_reader :package_json_file, :credentials, :dependency_files

        def package_json_may_be_for_library?
          return false unless project_name
          return false if project_name.match?(/\{\{.*\}\}/)
          return false unless parsed_package_json["version"]
          return false if parsed_package_json["private"]

          true
        end

        def npm_response_matches_package_json?
          project_description = parsed_package_json["description"]
          return false unless project_description

          # Check if the project is listed on npm. If it is, it's a library
          return false unless registry_response.status == 200

          registry_response_body = registry_response.body.dup.force_encoding("UTF-8").encode
          registry_response_body.include?(project_description)
        end

        def project_name
          parsed_package_json.fetch("name", nil)
        end

        def escaped_project_name
          project_name&.gsub("/", "%2F")
        end

        def parsed_package_json
          @parsed_package_json ||= JSON.parse(package_json_file.content)
        end

        def registry_response
          return @registry_response if defined?(@registry_response)

          url = "#{registry.chomp('/')}/#{escaped_project_name}"
          @registry_response = Dependabot::RegistryClient.get(url: url)
        rescue Excon::Error::Socket, Excon::Error::Timeout, URI::InvalidURIError
          nil
        end

        def registry
          NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: nil,
            credentials: credentials,
            npmrc_file: dependency_files.find { |f| f.name.end_with?(".npmrc") },
            yarnrc_file: dependency_files.find { |f| f.name.end_with?(".yarnrc") },
            yarnrc_yml_file: dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
          ).registry_from_rc(project_name)
        end
      end
    end
  end
end
