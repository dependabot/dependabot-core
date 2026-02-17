# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/update_checkers"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Conda < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_conda_checker,
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
              requirement: new_requirement,
              channel: original_source[:extras]
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
        def fetch_latest_version_via_conda_checker
          conda_checker = conda_update_checker
          return nil unless conda_checker

          latest = conda_checker.latest_version
          Dependabot.logger.info("Conda UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue Dependabot::DependabotError, Excon::Error, JSON::ParserError => e
          Dependabot.logger.debug("Error checking Conda package #{package_name}: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def conda_update_checker
          @conda_update_checker ||= T.let(
            build_conda_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_conda_update_checker
          conda_dependency = build_conda_dependency
          return nil unless conda_dependency

          Dependabot.logger.info("Delegating to conda UpdateChecker for package: #{conda_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("conda").new(
            dependency: conda_dependency,
            dependency_files: build_conda_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_conda_dependency
          return nil unless package_name

          version = current_version || extract_version_from_requirement

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: version ? "==#{version}" : nil,
              groups: ["dependencies"],
              file: "environment.yml",
              source: nil
            }],
            package_manager: "conda"
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          # Handle conda version operators: =, ==, >=, <=, >, <, !=, ~=
          version_part = req_string.sub(/\A(?:==|>=|<=|~=|!=|>|<|=)\s*/, "")
          return version_part if version_part.match?(/\A\d+(?:\.\d+)*(?:[._+-][\w.+-]*)?\z/)

          nil
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_conda_dependency_files
          version = current_version || extract_version_from_requirement
          requirement = version ? "==#{version}" : nil
          channel = source[:extras]

          # Build channel prefix if present
          dep_string = channel ? "#{channel}::#{package_name}" : T.must(package_name)
          dep_string = "#{dep_string}#{requirement}" if requirement

          yaml_content = <<~YAML
            name: dependabot-pre-commit-check
            dependencies:
              - #{dep_string}
          YAML

          [
            Dependabot::DependencyFile.new(
              name: "environment.yml",
              content: yaml_content
            )
          ]
        end

        sig do
          params(
            package_name: T.nilable(String),
            requirement: T.nilable(String),
            channel: T.nilable(String)
          ).returns(String)
        end
        def build_original_string(package_name:, requirement:, channel:)
          base = channel ? "#{channel}::#{package_name}" : package_name.to_s
          # Normalize == back to = for conda format
          normalized_req = requirement&.sub(/\A==/, "=")
          base = "#{base}#{normalized_req}" if normalized_req
          base
        end

        sig { params(original_requirement: T.nilable(String), new_version: String).returns(String) }
        def build_updated_requirement(original_requirement, new_version)
          return "==#{new_version}" unless original_requirement

          # Preserve the original operator
          operator_match = original_requirement.match(/\A(?<op>==|>=|<=|~=|!=|>|<|=)\s*/)
          if operator_match
            "#{operator_match[:op]}#{new_version}"
          else
            "==#{new_version}"
          end
        end
      end
    end
  end
end

Dependabot::PreCommit::AdditionalDependencyCheckers.register(
  "conda",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Conda
)
