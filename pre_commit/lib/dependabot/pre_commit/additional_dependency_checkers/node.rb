# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/update_checkers"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Node < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_npm_checker,
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
        def fetch_latest_version_via_npm_checker
          npm_checker = npm_update_checker
          return nil unless npm_checker

          latest = npm_checker.latest_version
          Dependabot.logger.info("Node UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue StandardError => e
          Dependabot.logger.debug("Error checking Node package #{package_name}: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def npm_update_checker
          @npm_update_checker ||= T.let(
            build_npm_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_npm_update_checker
          npm_dependency = build_npm_dependency
          return nil unless npm_dependency

          Dependabot.logger.info("Delegating to npm_and_yarn UpdateChecker for package: #{npm_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("npm_and_yarn").new(
            dependency: npm_dependency,
            dependency_files: build_npm_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_npm_dependency
          return nil unless package_name

          version = current_version || extract_version_from_requirement

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: version || nil,
              groups: ["dependencies"],
              file: "package.json",
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          version_part = req_string.sub(/\A[~^]|[><=]+\s*/, "")
          return version_part if version_part.match?(/\A\d+(?:\.\d+)*(?:-[\w.]+)?(?:\+[\w.]+)?\z/)

          nil
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_npm_dependency_files
          version = current_version || extract_version_from_requirement
          content = JSON.generate(
            {
              "name" => "dependabot-pre-commit-check",
              "version" => "0.0.1",
              "dependencies" => {
                T.must(package_name) => version || "*"
              }
            }
          )

          [
            Dependabot::DependencyFile.new(
              name: "package.json",
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
  "node",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Node
)
