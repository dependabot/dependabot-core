# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/deno/version"

module Dependabot
  module Deno
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def initialize(dependency:, ignored_versions:, security_advisories:)
          @dependency = dependency
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
        end

        sig { returns(T.nilable(Deno::Version)) }
        def latest_version
          @latest_version ||= T.let(
            fetch_latest_version,
            T.nilable(Deno::Version)
          )
        end

        sig { returns(T.nilable(Deno::Version)) }
        def lowest_security_fix_version
          versions = available_versions
          versions = filter_vulnerable_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.min
        end

        sig { returns(T::Array[Deno::Version]) }
        def available_versions
          @available_versions ||= T.let(
            fetch_available_versions,
            T.nilable(T::Array[Deno::Version])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T.nilable(Deno::Version)) }
        def fetch_latest_version
          versions = filter_prerelease_versions(available_versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        sig { returns(T::Array[Deno::Version]) }
        def fetch_available_versions
          source_type = dependency.requirements.first&.dig(:source, :type)

          case source_type
          when "jsr"
            fetch_jsr_versions
          when "npm"
            fetch_npm_versions
          else
            []
          end
        end

        sig { returns(T::Array[Deno::Version]) }
        def fetch_jsr_versions
          name = dependency.name
          url = "https://jsr.io/#{name}/meta.json"

          response = Dependabot::RegistryClient.get(url: url)
          data = JSON.parse(response.body)

          data.fetch("versions", {}).filter_map do |version_str, meta|
            next if meta.is_a?(Hash) && meta["yanked"]
            next unless Deno::Version.correct?(version_str)

            Deno::Version.new(version_str)
          end
        end

        sig { returns(T::Array[Deno::Version]) }
        def fetch_npm_versions
          name = dependency.name
          url = "https://registry.npmjs.org/#{name}"

          response = Dependabot::RegistryClient.get(url: url)
          data = JSON.parse(response.body)

          data.fetch("versions", {}).filter_map do |version_str, _meta|
            next unless Deno::Version.correct?(version_str)

            Deno::Version.new(version_str)
          end
        end

        sig { params(versions: T::Array[Deno::Version]).returns(T::Array[Deno::Version]) }
        def filter_prerelease_versions(versions)
          current = if dependency.version && Deno::Version.correct?(dependency.version)
                      Deno::Version.new(T.must(dependency.version))
                    end

          return versions if current&.prerelease?

          versions.reject(&:prerelease?)
        end

        sig { params(versions: T::Array[Deno::Version]).returns(T::Array[Deno::Version]) }
        def filter_ignored_versions(versions)
          versions.reject do |v|
            ignored_versions.any? do |req_str|
              req = Gem::Requirement.new(req_str.split(",").map(&:strip))
              req.satisfied_by?(v)
            rescue Gem::Requirement::BadRequirementError
              false
            end
          end
        end

        sig { params(versions: T::Array[Deno::Version]).returns(T::Array[Deno::Version]) }
        def filter_vulnerable_versions(versions)
          versions.reject do |v|
            security_advisories.any? { |a| a.vulnerable?(v) }
          end
        end
      end
    end
  end
end
