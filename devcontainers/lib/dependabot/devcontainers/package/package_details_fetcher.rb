# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/devcontainers"
require "dependabot/devcontainers/version"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Devcontainers
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def fetch_package_releases
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])

          begin
            Dependabot.logger.info("Fetching package info (Dev Containers) for #{dependency.name}")

            cmd = "devcontainer features info tags #{dependency.name} --output-format json"
            Dependabot.logger.info("Running command: `#{cmd}`")

            output = SharedHelpers.run_shell_command(cmd, stderr_to_stdout: false)
            package_metadata = JSON.parse(output).fetch("publishedTags")

            package_metadata.each do |release|
              next unless version_class.correct?(release) &&
                          T.cast(version_class.new(release), Dependabot::Devcontainers::Version)

              releases << Dependabot::Package::PackageRelease.new(
                version: Devcontainers::Version.new(release),
                released_at: nil
              )
            end

            releases.sort_by!(&:version)
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for dev container packages: #{e.message}")
            releases
          end
        end

        sig do
          params(release: Dependabot::Package::PackageRelease).returns(Dependabot::Package::PackageRelease)
        end
        def fetch_release_metadata(release:)
          Dependabot.logger.info("Fetching release metadata (Dev Containers) for #{dependency.name}:#{release.version}")

          response = fetch_response(release: release)
          return release unless response.status == 200

          metadata_json = JSON.parse(response.body)["layers"][0]
          released_at = metadata_json["annotations"]["org.opencontainers.image.created"]

          release.instance_variable_set(:@tag, metadata_json["digest"])

          # Annotations properties are optional, So getting a release date is not guaranteed.
          # https://specs.opencontainers.org/image-spec/annotations/#annotations
          release.instance_variable_set(:@released_at,
                                        released_at ? Time.parse(released_at) : nil)

          release
        rescue StandardError => e
          Dependabot.logger.error("Error while fetching metadata (Dev Container) " \
                                  "for #{dependency.name}: #{e.message}")
          release
        end

        private

        sig { params(release: Dependabot::Package::PackageRelease).returns(Excon::Response) }
        def fetch_response(release:)
          url = "https://#{ref_registry}/v2/#{ref_namespace}/#{ref_id}/manifests/#{release.version}"

          Dependabot::RegistryClient.get(url: url,
                                         headers: { "Accept" => "application/vnd.oci.image.manifest.v1+json",
                                                    "user-agent": "devcontainer",
                                                    "Authorization" => "Bearer #{auth_token}" })
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(String) }
        def ref_registry
          T.must(dependency.name.split("/")[0])
        end

        sig { returns(String) }
        def ref_namespace
          T.must(dependency.name.split("/")[1...-1]).join("/")
        end

        sig { returns(String) }
        def ref_id
          T.must(dependency.name.split("/")[-1])
        end

        # ghcr.io needs a auth token to access the package metadata, We use following
        # token system to fetch on the fly auth token for authentication.
        # https://docs.docker.com/registry/spec/auth/token/#how-to-authenticate
        # the idea was borrowed from https://github.com/devcontainers/cli project
        sig { returns(T.nilable(String)) }
        def auth_token
          token_url = "https://#{ref_registry}/token?service=ghcr.io&scope=repository:#{ref_namespace}/#{ref_id}:pull"

          response = Excon.get(token_url, headers: { "Accept" => "application/json" })
          JSON.parse(response.body)["token"]
        end
      end
    end
  end
end
