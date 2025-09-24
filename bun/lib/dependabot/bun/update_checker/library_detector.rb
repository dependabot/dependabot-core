# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/bun/update_checker"
require "dependabot/shared_helpers"

module Dependabot
  module Bun
    class UpdateChecker
      class LibraryDetector
        extend T::Sig

        sig do
          params(
            package_json_file: Dependabot::DependencyFile,
            credentials: T::Array[Dependabot::Credential],
            dependency_files: T::Array[Dependabot::DependencyFile]
          )
            .void
        end
        def initialize(package_json_file:, credentials:, dependency_files:)
          @package_json_file = package_json_file
          @credentials = credentials
          @dependency_files = dependency_files
        end

        sig { returns(T::Boolean) }
        def library?
          return false unless package_json_may_be_for_library?

          npm_response_matches_package_json?
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :package_json_file

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Boolean) }
        def package_json_may_be_for_library?
          return false unless project_name
          return false if T.must(project_name).match?(/\{\{.*\}\}/)
          return false unless parsed_package_json["version"]
          return false if parsed_package_json["private"]

          true
        end

        sig { returns(T::Boolean) }
        def npm_response_matches_package_json?
          project_description = parsed_package_json["description"]
          return false unless project_description

          # Check if the project is listed on npm. If it is, it's a library
          url = "#{registry.chomp('/')}/#{escaped_project_name}"
          @project_npm_response ||= T.let(
            Dependabot::RegistryClient.get(url: url),
            T.nilable(Excon::Response)
          )
          return false unless @project_npm_response.status == 200

          @project_npm_response.body.dup.force_encoding("UTF-8").encode
                               .include?(project_description)
        rescue Excon::Error::Socket, Excon::Error::Timeout, URI::InvalidURIError
          false
        end

        sig { returns(T.nilable(String)) }
        def project_name
          parsed_package_json.fetch("name", nil)
        end

        sig { returns(T.nilable(String)) }
        def escaped_project_name
          project_name&.gsub("/", "%2F")
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_package_json
          @parsed_package_json ||= T.let(
            JSON.parse(T.must(package_json_file.content)),
            T.nilable(T::Hash[String, T.untyped])
          )
        end

        sig { returns(String) }
        def registry
          Bun::Package::RegistryFinder.new(
            dependency: nil,
            credentials: credentials,
            npmrc_file: dependency_files.find { |f| f.name.end_with?(".npmrc") }
          ).registry_from_rc(T.must(project_name)) || "https://registry.npmjs.org"
        end
      end
    end
  end
end
