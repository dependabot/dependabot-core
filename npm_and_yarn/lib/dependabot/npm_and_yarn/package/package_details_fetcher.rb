# typed: strict
# frozen_string_literal: true

require "json"
require "excon"
require "time"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/npm_and_yarn/package/registry_finder"

module Dependabot
  module NpmAndYarn
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:
        )
          @dependency = T.let(dependency, Dependabot::Dependency)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])

          @npm_details = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          @dist_tags = T.let(nil, T.nilable(T::Hash[String, String]))
          @registry_finder = T.let(nil, T.nilable(Package::RegistryFinder))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch
          package_data = fetch_npm_details
          Dependabot::Package::PackageDetails.new(
            dependency: @dependency,
            releases: package_data ? parse_versions(package_data) : [],
            dist_tags: dist_tags
          )
        end

        sig { returns(T::Boolean) }
        def valid_npm_details?
          !dist_tags.nil?
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def npm_details
          @npm_details ||= fetch_npm_details
        end

        sig { returns(T::Boolean) }
        def custom_registry?
          registry_finder.custom_registry?
        end

        private

        sig do
          params(
            npm_data: T::Hash[String, T.untyped]
          ).returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def parse_versions(npm_data)
          time_data = npm_data["time"] || {}
          versions_data = npm_data["versions"] || {}

          latest_version = npm_data.dig("dist-tags", "latest")

          versions_data.filter_map do |version, details|
            next unless Dependabot::NpmAndYarn::Version.correct?(version)

            package_type = details.dig("repository", "type")

            deprecated = details["deprecated"]

            Dependabot::Package::PackageRelease.new(
              version: Version.new(version),
              released_at: time_data[version] ? Time.parse(time_data[version]) : nil,
              yanked: deprecated ? true : false,
              yanked_reason: deprecated.is_a?(String) ? deprecated : nil,
              downloads: nil,
              latest: latest_version.to_s == version,
              url: package_version_url(version),
              package_type: package_type,
              language: package_language(details)
            )
          end.sort_by(&:version).reverse
        end

        sig { params(version: String).returns(String) }
        def package_version_url(version)
          "#{dependency_registry}/#{@dependency.name}/v/#{version}"
        end

        sig do
          params(version_details: T::Hash[String, T.untyped])
            .returns(T.nilable(Dependabot::Package::PackageLanguage))
        end
        def package_language(version_details)
          node_requirement = version_details.dig("engines", "node")

          return nil unless node_requirement

          if node_requirement
            Dependabot::Package::PackageLanguage.new(
              name: "node",
              version: nil,
              requirement: Requirement.new(node_requirement)
            )
          end
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig { returns(T.nilable(T::Hash[String, String])) }
        def dist_tags
          @dist_tags ||= npm_details&.fetch("dist-tags", nil)
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def fetch_npm_details
          npm_response = fetch_npm_response
          check_npm_response(npm_response) if npm_response
          JSON.parse(npm_response.body)
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket, RegistryError => e
          return nil if git_dependency?

          raise_npm_details_error(e)
        end

        sig { returns(Excon::Response) }
        def fetch_npm_response
          response = Dependabot::RegistryClient.get(
            url: dependency_url,
            headers: registry_auth_headers
          )

          # If response is successful, return it
          return response if response.status.to_s.start_with?("2")

          # If the registry is public (not explicitly private) and the request fails, return the response as is
          return response if dependency_registry == "registry.npmjs.org"

          # If a private registry returns a 500 error, check authentication
          return response unless response.status == 500
          return response unless registry_auth_headers["Authorization"]

          auth = registry_auth_headers["Authorization"]
          return response unless auth&.start_with?("Basic")

          decoded_token = Base64.decode64(auth.gsub("Basic ", "")).strip

          # Ensure decoded token is not empty and contains a colon
          if decoded_token.empty? || !decoded_token.include?(":")
            raise PrivateSourceAuthenticationFailure, "Malformed basic auth credentials for #{dependency_registry}"
          end

          username, password = decoded_token.split(":")

          Dependabot::RegistryClient.get(
            url: dependency_url,
            options: {
              user: username,
              password: password
            }
          )
        rescue URI::InvalidURIError => e
          raise DependencyFileNotResolvable, e.message
        end

        sig { params(npm_response: Excon::Response).void }
        def check_npm_response(npm_response)
          return if git_dependency?

          if private_dependency_not_reachable?(npm_response)
            raise PrivateSourceAuthenticationFailure, dependency_registry
          end

          # handles scenario when private registry returns a server error 5xx
          if private_dependency_server_error?(npm_response)
            msg = "Server error #{npm_response.status} returned while accessing registry" \
                  " #{dependency_registry}."
            raise DependencyFileNotResolvable, msg
          end

          status = npm_response.status

          # handles issue when status 200 is returned from registry but with an invalid JSON object
          if status.to_s.start_with?("2") && response_invalid_json?(npm_response)
            msg = "Invalid JSON object returned from registry #{dependency_registry}."
            Dependabot.logger.warn("#{msg} Response body (truncated) : #{npm_response.body[0..500]}...")
            raise DependencyFileNotResolvable, msg
          end

          return if status.to_s.start_with?("2")

          # Ignore 404s from the registry for updates where a lockfile doesn't
          # need to be generated. The 404 won't cause problems later.
          return if status == 404 && dependency.version.nil?

          msg = "Got #{status} response with body #{npm_response.body}"
          raise RegistryError.new(status, msg)
        end

        sig { params(error: StandardError).void }
        def raise_npm_details_error(error)
          raise if dependency_registry == "registry.npmjs.org"
          raise unless error.is_a?(Excon::Error::Timeout)

          raise PrivateSourceTimedOut, dependency_registry
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def private_dependency_not_reachable?(npm_response)
          return true if npm_response.body.start_with?(/user ".*?" is not a /)
          return false unless [401, 402, 403, 404].include?(npm_response.status)

          # Check whether this dependency is (likely to be) private
          if dependency_registry == "registry.npmjs.org"
            return false unless dependency.name.start_with?("@")

            web_response = Dependabot::RegistryClient.get(url: "https://www.npmjs.com/package/#{dependency.name}")
            # NOTE: returns 429 when the login page is rate limited
            return web_response.body.include?("Forgot password?") ||
                   web_response.status == 429
          end

          true
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def private_dependency_server_error?(npm_response)
          if [500, 501, 502, 503].include?(npm_response.status)
            Dependabot.logger.warn("#{dependency_registry} returned code #{npm_response.status} with " \
                                   "body #{npm_response.body}.")
            return true
          end
          false
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def response_invalid_json?(npm_response)
          result = JSON.parse(npm_response.body)
          result.is_a?(Hash) || result.is_a?(Array)
          false
        rescue JSON::ParserError, TypeError
          true
        end

        sig { returns(String) }
        def dependency_url
          registry_finder.dependency_url
        end

        sig { returns(T::Hash[String, String]) }
        def registry_auth_headers
          registry_finder.auth_headers
        end

        sig { returns(String) }
        def dependency_registry
          registry_finder.registry
        end

        sig { returns(Package::RegistryFinder) }
        def registry_finder
          @registry_finder ||= Package::RegistryFinder.new(
            dependency: dependency,
            credentials: credentials,
            npmrc_file: npmrc_file,
            yarnrc_file: yarnrc_file,
            yarnrc_yml_file: yarnrc_yml_file
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def npmrc_file
          dependency_files.find { |f| f.name.end_with?(".npmrc") }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc") }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          # ignored_version/raise_on_ignored are irrelevant.
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end
      end
    end
  end
end
