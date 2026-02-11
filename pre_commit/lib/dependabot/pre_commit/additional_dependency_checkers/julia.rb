# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Julia < Base
        extend T::Sig

        GENERAL_REGISTRY_RAW_URL = "https://raw.githubusercontent.com/JuliaRegistries/General/master"

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_from_registry,
            T.nilable(String)
          )
        end

        sig { override.params(latest_version: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(latest_version)
          requirements.map do |original_req|
            original_source = original_req[:source]
            next original_req unless original_source.is_a?(Hash)
            next original_req unless original_source[:type] == "additional_dependency"

            original_requirement = original_req[:requirement]
            new_requirement = build_updated_requirement(original_requirement, latest_version)

            new_original_string = build_original_string(
              package_name: original_source[:original_name] || original_source[:package_name],
              requirement: new_requirement
            )

            new_source = original_source.merge(original_string: new_original_string)

            original_req.merge(
              requirement: new_requirement,
              source: new_source
            )
          end
        end

        private

        sig { returns(T.nilable(String)) }
        def fetch_latest_version_from_registry
          name = T.must(package_name)
          url = registry_versions_url(name)

          Dependabot.logger.info("Fetching Julia package versions for #{name} from General registry")

          response = Excon.get(url, idempotent: true, **Dependabot::SharedHelpers.excon_defaults)

          return nil unless response.status == 200

          parse_latest_version(response.body)
        rescue Excon::Error => e
          Dependabot.logger.debug("Error fetching Julia package #{package_name}: #{e.message}")
          nil
        end

        sig { params(package_name: String).returns(String) }
        def registry_versions_url(package_name)
          first_letter = package_name[0]
          "#{GENERAL_REGISTRY_RAW_URL}/#{first_letter}/#{package_name}/Versions.toml"
        end

        sig { params(toml_body: String).returns(T.nilable(String)) }
        def parse_latest_version(toml_body)
          versions = extract_non_yanked_versions(toml_body)
          return nil if versions.empty?

          versions
            .select { |v| v.match?(/\A\d+(?:\.\d+)*\z/) }
            .max_by { |v| Gem::Version.new(v) }
        end

        sig { params(toml_body: String).returns(T::Array[String]) }
        def extract_non_yanked_versions(toml_body)
          versions = T.let([], T::Array[String])
          current_version = T.let(nil, T.nilable(String))
          yanked = T.let(false, T::Boolean)

          toml_body.each_line do |line|
            line = line.strip

            if (match = line.match(/\A\["([^"]+)"\]\z/))
              versions << current_version if current_version && !yanked
              current_version = match[1]
              yanked = false
            elsif line.match?(/\Ayanked\s*=\s*true\z/)
              yanked = true
            end
          end

          versions << current_version if current_version && !yanked
          versions
        end

        sig do
          params(
            package_name: T.nilable(String),
            requirement: T.nilable(String)
          ).returns(String)
        end
        def build_original_string(package_name:, requirement:)
          base = package_name.to_s
          base = "#{base}@#{requirement}" if requirement
          base
        end

        sig { params(original_requirement: T.nilable(String), new_version: String).returns(String) }
        def build_updated_requirement(original_requirement, new_version)
          return new_version unless original_requirement

          operator_match = original_requirement.match(/\A(?<op>[~^]|[><=]+)\s*/)
          if operator_match
            "#{operator_match[:op]}#{new_version}"
          else
            new_version
          end
        end
      end
    end
  end
end

Dependabot::PreCommit::AdditionalDependencyCheckers.register(
  "julia",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Julia
)
