# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class LibraryDetector
          def initialize(package_json_file:)
            @package_json_file = package_json_file
          end

          def library?
            return false unless package_json_may_be_for_library?

            npm_response_matches_package_json?
          end

          private

          attr_reader :package_json_file

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
            @project_npm_response ||= Excon.get(
              "https://registry.npmjs.org/#{escaped_project_name}",
              idempotent: true,
              **SharedHelpers.excon_defaults
            )

            return false unless @project_npm_response.status == 200
            @project_npm_response.body.force_encoding("UTF-8").encode.
              include?(project_description)
          rescue Excon::Error::Socket, Excon::Error::Timeout
            false
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
        end
      end
    end
  end
end
