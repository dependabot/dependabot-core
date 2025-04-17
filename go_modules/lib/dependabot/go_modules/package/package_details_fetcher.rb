# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/go_modules/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/requirement"
require "dependabot/go_modules/resolvability_errors"

module Dependabot
  module GoModules
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        RESOLVABILITY_ERROR_REGEXES = T.let(
          [
            # Package url/proxy doesn't include any redirect meta tags
            /no go-import meta tags/,
            # Package url 404s
            /404 Not Found/,
            /Repository not found/,
            /unrecognized import path/,
            /malformed module path/,
            # (Private) module could not be fetched
            /module .*: git ls-remote .*: exit status 128/m
          ].freeze,
          T::Array[Regexp]
        )
        # The module was retracted from the proxy
        # OR the version of Go required is greater than what Dependabot supports
        # OR other go.mod version errors
        INVALID_VERSION_REGEX = /(go: loading module retractions for)|(version "[^"]+" invalid)/m
        PSEUDO_VERSION_REGEX = /\b\d{14}-[0-9a-f]{12}$/

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            goprivate: String
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, goprivate:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @goprivate = T.let(goprivate, String)

          @source_type = T.let(nil, T.nilable(String))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(String) }
        attr_reader :goprivate

        # rubocop:disable Metrics/AbcSize,Metrics/PerceivedComplexity
        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_available_versions
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              manifest = parse_manifest

              # Set up an empty go.mod so 'go list -m' won't attempt to download dependencies. This
              # appears to be a side effect of operating with modules included in GOPRIVATE. We'll
              # retain any exclude directives to omit those versions.
              File.write("go.mod", "module dummy\n")
              manifest["Exclude"]&.each do |r|
                SharedHelpers.run_shell_command("go mod edit -exclude=#{r['Path']}@#{r['Version']}")
              end

              # Turn off the module proxy for private dependencies
              env = { "GOPRIVATE" => @goprivate }

              versions_json = SharedHelpers.run_shell_command(
                "go list -m -versions -json #{dependency.name}",
                fingerprint: "go list -m -versions -json <dependency_name>",
                env: env
              )
              version_strings = JSON.parse(versions_json)["Versions"]

              return [package_release(version: T.must(dependency.version))] if version_strings.nil?

              version_info = version_strings.select { |v| version_class.correct?(v) }
                                            .map { |v| version_class.new(v) }

              package_releases = []

              version_info.map do |version|
                package_releases << package_release(
                  version: version.to_s
                )
              end

              return package_releases
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          retry if transitory_failure?(e) && retry_count < 2

          ResolvabilityErrors.handle(e.message, goprivate: @goprivate)
          [package_release(version: T.must(dependency.version))]
        end
        # rubocop:enable Metrics/AbcSize,Metrics/PerceivedComplexity

        sig { params(error: StandardError).returns(T::Boolean) }
        def transitory_failure?(error)
          return true if error.message.include?("EOF")

          error.message.include?("Internal Server Error")
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def go_mod
          @go_mod ||= T.let(dependency_files.find { |f| f.name == "go.mod" }, T.nilable(Dependabot::DependencyFile))
        end

        sig do
          params(
            version: String
          ).returns(Dependabot::Package::PackageRelease)
        end
        def package_release(version:)
          Dependabot::Package::PackageRelease.new(
            version: GoModules::Version.new(version)
          )
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parse_manifest
          SharedHelpers.in_a_temporary_directory do
            File.write("go.mod", T.must(go_mod).content)
            json = SharedHelpers.run_shell_command("go mod edit -json")

            JSON.parse(json) || {}
          end
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
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
            ), T.nilable(Dependabot::Package::PackageDetails)
          )
        end
      end
    end
  end
end
