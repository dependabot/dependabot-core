# typed: strict
# frozen_string_literal: true

require "json"
require "excon"
require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/bazel/update_checker"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class CargoVersionResolver
        extend T::Sig

        CRATES_IO_API_URL = "https://crates.io/api/v1"

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
          @crate_name = T.let(dependency.name, String)
        end

        sig { returns(T.nilable(String)) }
        def latest_version
          versions = fetch_versions
          return nil if versions.empty?

          # Filter out yanked versions
          valid_versions = versions.reject { |v| yanked?(v) }
          return nil if valid_versions.empty?

          requirement = extract_requirement
          if requirement
            compatible_versions = valid_versions.select { |v| matches_requirement?(v, requirement) }
            return nil if compatible_versions.empty?

            compatible_versions.max_by { |v| version_sort_key(v) }
          else
            valid_versions.max_by { |v| version_sort_key(v) }
          end
        end

        sig { returns(T::Array[String]) }
        def fetch_versions
          url = "#{CRATES_IO_API_URL}/crates/#{@crate_name}/versions"
          response = Excon.get(
            url,
            idempotent: true,
            headers: { "User-Agent" => "Dependabot" },
            **SharedHelpers.excon_defaults
          )

          return [] unless response.status == 200

          data = JSON.parse(response.body)
          versions_data = data["versions"]
          return [] unless versions_data.is_a?(Array)

          versions_data.filter_map { |v| v["num"] }
        rescue Excon::Error, JSON::ParserError => e
          Dependabot.logger.warn("Failed to fetch Cargo versions for #{@crate_name}: #{e.message}")
          []
        end

        sig { params(version: String).returns(T::Boolean) }
        def yanked?(version)
          url = "#{CRATES_IO_API_URL}/crates/#{@crate_name}/#{version}"
          response = Excon.get(
            url,
            idempotent: true,
            headers: { "User-Agent" => "Dependabot" },
            **SharedHelpers.excon_defaults
          )

          return false unless response.status == 200

          data = JSON.parse(response.body)
          version_data = data["version"]
          return false unless version_data

          version_data["yanked"] == true
        rescue JSON::ParserError, Excon::Error::Timeout
          false
        end

        private

        sig { returns(T.nilable(String)) }
        def extract_requirement
          req = @dependency.requirements.first
          return nil unless req

          req[:requirement]
        end

        sig { params(version: String, requirement: String).returns(T::Boolean) }
        def matches_requirement?(version, requirement)
          case requirement
          when /^=/
            version == requirement.delete_prefix("=")
          when /^\^/
            req_version = requirement.delete_prefix("^")
            version_compatible?(version, req_version)
          when /^~/
            req_version = requirement.delete_prefix("~")
            version_tilde_compatible?(version, req_version)
          else
            version_compatible?(version, requirement)
          end
        end

        sig { params(version: String, req_version: String).returns(T::Boolean) }
        def version_compatible?(version, req_version)
          v_parts = version.split(".").map(&:to_i)
          req_parts = req_version.split(".").map(&:to_i)

          v_major = v_parts[0]
          return false if v_major != req_parts[0]
          return false if v_major.nil? ? false : (v_major.zero? && v_parts[1] != req_parts[1])

          (v_parts <=> req_parts) >= 0
        end

        sig { params(version: String, req_version: String).returns(T::Boolean) }
        def version_tilde_compatible?(version, req_version)
          v_parts = version.split(".").map(&:to_i)
          req_parts = req_version.split(".").map(&:to_i)

          # Must match major.minor
          return false if v_parts[0] != req_parts[0]
          return false if v_parts[1] != req_parts[1]

          # Patch version must be >= requirement
          (v_parts[2] || 0) >= (req_parts[2] || 0)
        end

        sig { params(version: String).returns(T::Array[T.any(Integer, String)]) }
        def version_sort_key(version)
          main, pre = version.split("-", 2)
          parts = T.must(main).split(".").map { |part| part.match?(/^\d+$/) ? part.to_i : 0 }
          if pre
            parts + [pre]
          else
            parts + [""]
          end
        end
      end
    end
  end
end
