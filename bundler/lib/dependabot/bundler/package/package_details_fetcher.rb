# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/bundler"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Bundler
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        require_relative "../update_checker/shared_bundler_helpers"
        include Dependabot::Bundler::UpdateChecker::SharedBundlerHelpers

        RELEASES_URL = "%s/api/v1/versions/%s.json"
        GEM_URL = "%s/gems/%s.gem"
        PACKAGE_TYPE = "gem"
        PACKAGE_LANGUAGE = "ruby"
        APPLICATION_JSON = "application/json"
        RUBYGEMS = "rubygems"
        GIT = "git"
        OTHER = "other"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials

          @source_type = T.let(nil, T.nilable(String))
          @options = T.let({}, T::Hash[Symbol, T.untyped])
          @repo_contents_path = T.let(nil, T.nilable(String))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { override.returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { override.returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options

        sig { override.returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          case source_type
          when GIT, OTHER
            package_details([])
          else
            rubygems_versions
          end
        end

        private

        # Example JSON Response Format:
        # eg https://rubygems.org/api/v1/versions/dependabot-common.json
        # response:
        # [
        # {
        #   authors: "Dependabot",
        #   built_at: "2025-03-20T00:00:00.000Z",
        #   created_at: "2025-03-20T14:48:33.295Z",
        #   description: "Dependabot-Common provides the shared code used across Dependabot. If you want support for
        #                 multiple package managers, you probably want the meta-gem dependabot-omnibus.",
        #   downloads_count: 382,
        #   metadata: {
        #   changelog_uri: "https://github.com/dependabot/dependabot-core/releases/tag/v0.302.0",
        #   bug_tracker_uri: "https://github.com/dependabot/dependabot-core/issues"
        #   },
        #   number: "0.302.0",
        #   summary: "Shared code used across Dependabot Core",
        #   platform: "ruby",
        #   rubygems_version: ">= 3.3.7",
        #   ruby_version: ">= 3.1.0",
        #   prerelease: false,
        #   licenses: [
        #   "MIT"
        #   ],
        #   requirements: [ ],
        #   sha: "e8ef286a91add81534c297425f2f2efc0c5671f3307307f7fad62c059ed8fca2",
        #   spec_sha: "cd0ac8f3462449bf19e7356dbc2ec83eec378b41702e03221ededc49875b1e1c"
        #   },
        #   {
        #   authors: "Dependabot",
        #   built_at: "2025-03-14T00:00:00.000Z",
        #   created_at: "2025-03-14T18:46:18.547Z",
        #   description: "Dependabot-Common provides the shared code used across Dependabot. If you want support for
        #                 multiple package managers, you probably want the meta-gem dependabot-omnibus.",
        #   downloads_count: 324,
        #   metadata: {
        #   changelog_uri: "https://github.com/dependabot/dependabot-core/releases/tag/v0.301.1",
        #   bug_tracker_uri: "https://github.com/dependabot/dependabot-core/issues"
        #   },
        #   number: "0.301.1",
        #   summary: "Shared code used across Dependabot Core",
        #   platform: "ruby",
        #   rubygems_version: ">= 3.3.7",
        #   ruby_version: ">= 3.1.0",
        #   prerelease: false,
        #   licenses: [
        #   "MIT"
        #   ],
        #   requirements: [ ],
        #   sha: "47e5948069571271d72c12f8c03106b415a00550857b6c5fb22aeb780cfe1da7",
        #   spec_sha: "7191388ac6fa0ea72ed7588f848b2b244a0dc5a4ec3e6b7c9d395296b0fa93d9"
        #   },
        # ...
        # ]
        sig { returns(Dependabot::Package::PackageDetails) }
        def rubygems_versions
          registry_url = get_url_from_dependency(dependency) || "https://rubygems.org"

          # TODO: Github private registry support
          # registry_url = "https://rubygems.pkg.github.com/#{OWNER_NAME}"
          # Corresponding API URL:
          # curl  -H "Accept: application/json" \
          #       -H "Authorization: Bearer <<TOKEN>>" \
          #       https://api.github.com/orgs/dsp-testing/packages/rubygems/json/version
          parsed_url = begin
            URI.parse(registry_url)
          rescue URI::InvalidURIError
            raise "Invalid registry URL: #{registry_url}"
          end

          # Handle GitHub Package Registry
          return github_packages_versions(registry_url) if parsed_url.host == "rubygems.pkg.github.com"

          response = registry_json_response_for_dependency(registry_url)

          unless response.status == 200
            error_details = "Status: #{response.status}"
            error_message = "Failed to fetch versions for '#{dependency.name}' from '#{registry_url}'. #{error_details}"
            Dependabot.logger.info(error_message)
            return package_details([])
          end

          registry_url = get_url_from_dependency(dependency) || "https://rubygems.org" # Get registry_url

          package_releases = JSON.parse(response.body).map do |release|
            gem_name_with_version = "#{@dependency.name}-#{release['number']}"
            package_release(
              version: release["number"],
              released_at: Time.parse(release["created_at"]),
              downloads: release["downloads_count"],
              url: format(GEM_URL, registry_url, gem_name_with_version),
              ruby_version: release["ruby_version"]
            )
          end

          package_details(package_releases)
        end

        sig { params(dependency: T.untyped).returns(T.nilable(String)) }
        def get_url_from_dependency(dependency)
          return nil unless dependency&.requirements&.any?

          first_requirement = dependency.requirements.first
          return nil unless first_requirement && first_requirement[:source]

          url = T.let(first_requirement[:source][:url], T.nilable(String))
          return nil unless url

          url.end_with?("/") ? url.chop : url
        end

        sig { params(registry_url: T.nilable(String)).returns(Excon::Response) }
        def registry_json_response_for_dependency(registry_url = "https://rubygems.org")
          url = format(RELEASES_URL, registry_url, dependency.name)

          Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => APPLICATION_JSON }
          )
        end

        sig { params(registry_url: String).returns(Dependabot::Package::PackageDetails) }
        def github_packages_versions(registry_url)
          # Extract org name from URL like "https://rubygems.pkg.github.com/dsp-testing/"
          org_name = registry_url.split("/").last

          # GitHub Packages API endpoint for RubyGems packages
          api_url = "https://api.github.com/orgs/#{org_name}/packages/rubygems/#{dependency.name}/versions"

          response = Dependabot::RegistryClient.get(
            url: api_url,
            headers: {
              "Accept" => "application/vnd.github.v3+json",
              "Authorization" => "Bearer #{github_token}"
            }
          )

          unless response.status == 200
            error_details = "Status: #{response.status}"
            error_details += " (Package not found in GitHub Registry)" if response.status == 404
            error_message = "Failed to fetch versions for '#{dependency.name}' from GitHub Packages. #{error_details}"
            Dependabot.logger.info(error_message)
            return package_details([])
          end

          begin
            versions_data = JSON.parse(response.body)
            package_releases = versions_data.map do |version_info|
              # GitHub Packages API returns different structure than RubyGems
              version_number = version_info["name"] # GitHub uses "name" for version
              created_at = version_info["created_at"]

              package_release(
                version: version_number,
                released_at: Time.parse(created_at),
                downloads: 0, # GitHub Packages doesn't provide download counts
                url: "#{registry_url}/gems/#{dependency.name}-#{version_number}.gem",
                ruby_version: nil # GitHub Packages API doesn't provide ruby version requirements
              )
            end

            package_details(package_releases)
          rescue JSON::ParserError => e
            Dependabot.logger.info("Failed to parse GitHub Packages response: #{e.message}")
            package_details([])
          end
        end

        sig { returns(T.nilable(String)) }
        def github_token
          github_credential = credentials.find do |cred|
            cred["type"] == "rubygems_server" && cred["host"] == "rubygems.pkg.github.com"
          end
          github_credential&.fetch("token", nil)
        end

        sig { params(req_string: String).returns(Requirement) }
        def language_requirement(req_string)
          Requirement.new(req_string)
        end

        sig { returns(T.nilable(String)) }
        def source_type
          return nil unless dependency.requirements.any?

          first_requirement = dependency.requirements.first
          return nil unless first_requirement && first_requirement[:source]

          first_requirement[:source][:type]
        end

        sig { override.returns(String) }
        def bundler_version
          @bundler_version ||= T.let(Helpers.bundler_version(lockfile), T.nilable(String))
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(Dependabot::Package::PackageDetails)
        end
        def package_details(releases)
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases.reverse.uniq(&:version)
            ),
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig do
          params(
            version: String,
            released_at: Time,
            downloads: Integer,
            url: String,
            ruby_version: T.nilable(String),
            yanked: T::Boolean
          ).returns(Dependabot::Package::PackageRelease)
        end
        def package_release(version:, released_at:, downloads:, url:, ruby_version:, yanked: false)
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Bundler::Version.new(version),
            released_at: released_at,
            yanked: yanked,
            yanked_reason: nil,
            downloads: downloads,
            url: url,
            package_type: PACKAGE_TYPE,
            language: Dependabot::Package::PackageLanguage.new(
              name: PACKAGE_LANGUAGE,
              version: nil,
              requirement: ruby_version ? language_requirement(ruby_version) : nil
            )
          )
        end
      end
    end
  end
end
