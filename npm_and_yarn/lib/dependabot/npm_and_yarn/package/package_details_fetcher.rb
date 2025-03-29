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

        GLOBAL_REGISTRY = "registry.npmjs.org"
        NPM_OFFICIAL_WEBSITE = "https://www.npmjs.com"

        API_AUTHORIZATION_KEY = "Authorization"
        API_AUTHORIZATION_VALUE_BASIC_PREFIX = "Basic"
        API_RESPONSE_STATUS_SUCCESS_PREFIX = "2"

        RELEASE_TIME_KEY = "time"
        RELEASE_VERSIONS_KEY = "versions"
        RELEASE_DIST_TAGS_KEY = "dist-tags"
        RELEASE_DIST_TAGS_LATEST_KEY = "latest"
        RELEASE_DIST_TAG_DATETIME_KEY = "time"
        RELEASE_ENGINES_KEY = "engines"
        RELEASE_LANGUAGE_KEY = "node"
        RELEASE_DEPRECATION_KEY = "deprecated"
        RELEASE_REPOSITORY_KEY = "repository"
        RELEASE_PACKAGE_TYPE_KEY = "type"
        RELEASE_PACKAGE_TYPE_GIT = "git"
        RELEASE_PACKAGE_TYPE_NPM = "npm"

        REGISTRY_FILE_NPMRC = ".npmrc"
        REGISTRY_FILE_YARNRC = ".yarnrc"
        REGISTRY_FILE_YARNRC_YML = ".yarnrc.yml"

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
          @version_endpoint_working = T.let(nil, T.nilable(T::Boolean))
          @yanked = T.let({}, T::Hash[Gem::Version, T.nilable(T::Boolean)])
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch
          package_data = npm_details
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

        sig { returns(String) }
        def dependency_url
          registry_finder.dependency_url
        end

        sig { params(version: Gem::Version).returns(T::Boolean) }
        def yanked?(version)
          return @yanked[version] || false if @yanked.key?(version)

          @yanked[version] =
            begin
              if dependency_registry == GLOBAL_REGISTRY
                status = Dependabot::RegistryClient.head(
                  url: registry_finder.tarball_url(version),
                  headers: registry_auth_headers
                ).status
              else
                status = Dependabot::RegistryClient.get(
                  url: dependency_url + "/#{version}",
                  headers: registry_auth_headers
                ).status

                if status == 404
                  # Some registries don't handle escaped package names properly
                  status = Dependabot::RegistryClient.get(
                    url: dependency_url.gsub("%2F", "/") + "/#{version}",
                    headers: registry_auth_headers
                  ).status
                end
              end

              version_not_found = status == 404
              version_not_found && version_endpoint_working?
            rescue Excon::Error::Timeout, Excon::Error::Socket
              # Give the benefit of the doubt if the registry is playing up
              false
            end

          @yanked[version] || false
        end

        private

        sig { returns(T.nilable(T::Boolean)) }
        def version_endpoint_working?
          return true if dependency_registry == GLOBAL_REGISTRY

          return @version_endpoint_working if @version_endpoint_working

          @version_endpoint_working =
            begin
              Dependabot::RegistryClient.get(
                url: dependency_url + "/#{RELEASE_DIST_TAGS_LATEST_KEY}",
                headers: registry_auth_headers
              ).status < 400
            rescue Excon::Error::Timeout, Excon::Error::Socket
              # Give the benefit of the doubt if the registry is playing up
              true
            end
          @version_endpoint_working
        end

        sig do
          params(
            npm_data: T::Hash[String, T.untyped]
          ).returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def parse_versions(npm_data)
          time_data = fetch_value_from_hash(npm_data, RELEASE_TIME_KEY)
          versions_data = fetch_value_from_hash(npm_data, RELEASE_VERSIONS_KEY)

          dist_tags = fetch_value_from_hash(npm_data, RELEASE_DIST_TAGS_KEY)
          latest_version = fetch_value_from_hash(dist_tags, RELEASE_DIST_TAG_DATETIME_KEY)

          versions_data.filter_map do |version, details|
            next unless Dependabot::NpmAndYarn::Version.correct?(version)

            package_type = infer_package_type(details)

            deprecated = fetch_value_from_hash(details, RELEASE_DEPRECATION_KEY)

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
          # Fetch the engines hash from the version details
          engines = version_details.is_a?(Hash) ? version_details[RELEASE_ENGINES_KEY] : nil
          # Check if engines is a hash and fetch the node requirement
          node_requirement = engines.is_a?(Hash) ? engines.fetch(RELEASE_LANGUAGE_KEY, nil) : nil

          return nil unless node_requirement

          if node_requirement
            Dependabot::Package::PackageLanguage.new(
              name: RELEASE_LANGUAGE_KEY,
              version: nil,
              requirement: Requirement.new(node_requirement)
            )
          end
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig { returns(T.nilable(T::Hash[String, String])) }
        def dist_tags
          @dist_tags ||= fetch_value_from_hash(npm_details, RELEASE_DIST_TAGS_KEY)
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def fetch_npm_details
          npm_response = fetch_npm_response
          check_npm_response(npm_response) if npm_response
          JSON.parse(npm_response.body)
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket, RegistryError => e
          if git_dependency?
            nil
          else
            raise_npm_details_error(e)
          end
        end

        sig { returns(Excon::Response) }
        def fetch_npm_response
          response = Dependabot::RegistryClient.get(
            url: dependency_url,
            headers: registry_auth_headers
          )

          # If response is successful, return it
          return response if response.status.to_s.start_with?(API_RESPONSE_STATUS_SUCCESS_PREFIX)

          # If the registry is public (not explicitly private) and the request fails, return the response as is
          return response if dependency_registry == GLOBAL_REGISTRY

          # If a private registry returns a 500 error, check authentication
          return response unless response.status == 500

          auth = fetch_value_from_hash(registry_auth_headers, API_AUTHORIZATION_KEY)
          return response unless auth

          return response unless auth&.start_with?(API_AUTHORIZATION_VALUE_BASIC_PREFIX)

          decoded_token = Base64.decode64(auth.gsub("#{API_AUTHORIZATION_VALUE_BASIC_PREFIX} ", "")).strip

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

        sig do
          params(
            details: T::Hash[String, T.untyped],
            git_dependency: T::Boolean
          )
            .returns(String)
        end
        def infer_package_type(details, git_dependency: false)
          return RELEASE_PACKAGE_TYPE_GIT if git_dependency

          repository = fetch_value_from_hash(details, RELEASE_REPOSITORY_KEY)

          case repository
          when String
            return repository.start_with?("git+") ? RELEASE_PACKAGE_TYPE_GIT : RELEASE_PACKAGE_TYPE_NPM
          when Hash
            type = fetch_value_from_hash(repository, RELEASE_PACKAGE_TYPE_KEY)
            return RELEASE_PACKAGE_TYPE_GIT if type == RELEASE_PACKAGE_TYPE_GIT
          end

          RELEASE_PACKAGE_TYPE_NPM
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
          if status.to_s.start_with?(API_RESPONSE_STATUS_SUCCESS_PREFIX) && response_invalid_json?(npm_response)
            msg = "Invalid JSON object returned from registry #{dependency_registry}."
            Dependabot.logger.warn("#{msg} Response body (truncated) : #{npm_response.body[0..500]}...")
            raise DependencyFileNotResolvable, msg
          end

          return if status.to_s.start_with?(API_RESPONSE_STATUS_SUCCESS_PREFIX)

          # Ignore 404s from the registry for updates where a lockfile doesn't
          # need to be generated. The 404 won't cause problems later.
          return if status == 404 && dependency.version.nil?

          msg = "Got #{status} response with body #{npm_response.body}"
          raise RegistryError.new(status, msg)
        end

        sig { params(error: StandardError).void }
        def raise_npm_details_error(error)
          raise if dependency_registry == GLOBAL_REGISTRY
          raise unless error.is_a?(Excon::Error::Timeout)

          raise PrivateSourceTimedOut, dependency_registry
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def private_dependency_not_reachable?(npm_response)
          return true if npm_response.body.start_with?(/user ".*?" is not a /)
          return false unless [401, 402, 403, 404].include?(npm_response.status)

          # Check whether this dependency is (likely to be) private
          if dependency_registry == GLOBAL_REGISTRY
            return false unless dependency.name.start_with?("@")

            web_response = Dependabot::RegistryClient.get(url: "#{NPM_OFFICIAL_WEBSITE}/package/#{dependency.name}")
            # NOTE: returns 429 when the login page is rate limited
            return web_response.body.include?("Forgot password?") ||
                   web_response.status == 429
          end

          true
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def private_dependency_server_error?(npm_response)
          if [500, 501, 502, 503].include?(npm_response.status)
            Dependabot.logger.warn(
              "#{dependency_registry} returned code #{npm_response.status} " \
              "with body #{npm_response.body}."
            )
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
          dependency_files.find { |f| f.name.end_with?(REGISTRY_FILE_NPMRC) }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_file
          dependency_files.find { |f| f.name.end_with?(REGISTRY_FILE_YARNRC) }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(REGISTRY_FILE_YARNRC_YML) }
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          # ignored_version/raise_on_ignored are irrelevant.
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end

        # This function safely retrieves a value for a given key from a Hash.
        # If the hash is valid and the key exists, it will return the value, otherwise nil.
        sig { params(hash: T.untyped, key: T.untyped).returns(T.untyped) }
        def fetch_value_from_hash(hash, key)
          return nil unless hash.is_a?(Hash) # Return nil if the hash is not a Hash

          hash.fetch(key, nil) # Fetch the value for the given key, defaulting to nil if not found
        end
      end
    end
  end
end
