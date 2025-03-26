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

        RELEASES_URL = "https://rubygems.org/api/v1/versions/%s.json"
        GEM_URL = "https://rubygems.org/gems/%s.gem"
        PACKAGE_TYPE = "gem"
        PACKAGE_LANGUAGE = "ruby"
        APPLICATION_JSON = "application/json"

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
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

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
        def fetch
          response = registry_json_response_for_dependency
          raise unless response.status == 200

          package_releases = JSON.parse(response.body).map do |release|
            Dependabot::Package::PackageRelease.new(
              version: Dependabot::Bundler::Version.new(release["number"]),
              released_at: Time.parse(release["created_at"]),
              yanked: false,
              yanked_reason: nil,
              downloads: release["downloads_count"],
              url: GEM_URL % "#{@dependency.name}-#{release['number']}",
              package_type: PACKAGE_TYPE,
              language: Dependabot::Package::PackageLanguage.new(
                name: PACKAGE_LANGUAGE,
                version: nil,
                requirement: language_requirement(release["ruby_version"])
              )
            )
          end

          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: package_releases.reverse.uniq(&:version)
          )
        end

        private

        sig { returns(Excon::Response) }
        def registry_json_response_for_dependency
          url = RELEASES_URL % dependency.name
          Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => APPLICATION_JSON }
          )
        end

        sig { params(req_string: String).returns(Requirement) }
        def language_requirement(req_string)
          Requirement.new(req_string)
        end
      end
    end
  end
end
