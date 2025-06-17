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

          @provider_url = T.let("https://package.elm-lang.org/packages/#{dependency.name}/releases.json",
                                T.nilable(String))
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

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end
      end
    end
  end
end
