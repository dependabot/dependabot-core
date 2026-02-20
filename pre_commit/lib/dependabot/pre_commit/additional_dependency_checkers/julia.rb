# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/update_checkers"
require "dependabot/julia/registry_client"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Julia < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_julia_checker,
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
        def fetch_latest_version_via_julia_checker
          checker = julia_update_checker
          return nil unless checker

          latest = checker.latest_version
          Dependabot.logger.info("Julia UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue Dependabot::DependabotError, Excon::Error => e
          Dependabot.logger.debug("Error checking Julia package #{package_name}: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def julia_update_checker
          @julia_update_checker ||= T.let(
            build_julia_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_julia_update_checker
          julia_dependency = build_julia_dependency
          return nil unless julia_dependency

          Dependabot.logger.info("Delegating to julia UpdateChecker for package: #{julia_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("julia").new(
            dependency: julia_dependency,
            dependency_files: build_julia_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_julia_dependency
          return nil unless package_name

          uuid = resolve_julia_uuid
          return nil unless uuid

          version = current_version || extract_version_from_requirement

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: version,
              groups: ["deps"],
              file: "Project.toml",
              source: nil
            }],
            package_manager: "julia",
            metadata: { julia_uuid: uuid }
          )
        end

        sig { returns(T.nilable(String)) }
        def resolve_julia_uuid
          @resolve_julia_uuid ||= T.let(
            begin
              client = Dependabot::Julia::RegistryClient.new(credentials: credentials)
              uuid = client.resolve_package_uuid(T.must(package_name))
              Dependabot.logger.info("Resolved Julia UUID for #{package_name}: #{uuid || 'not found'}")
              uuid
            rescue StandardError => e
              Dependabot.logger.warn("Failed to resolve Julia UUID for #{package_name}: #{e.message}")
              nil
            end,
            T.nilable(String)
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          version_part = req_string.sub(/\A(?:[~^]|[><=]+)\s*/, "")
          return version_part if version_part.match?(/\A\d+(?:\.\d+)*\z/)

          nil
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_julia_dependency_files
          name = T.must(package_name)
          uuid = resolve_julia_uuid || "00000000-0000-0000-0000-000000000000"
          version = current_version || extract_version_from_requirement
          content = <<~TOML
            [deps]
            #{name} = "#{uuid}"

            [compat]
            #{name} = "#{version || '*'}"
          TOML

          [
            Dependabot::DependencyFile.new(
              name: "Project.toml",
              content: content
            )
          ]
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
