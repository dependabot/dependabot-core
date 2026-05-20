# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/update_checkers"
require "dependabot/pub/version"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Dart < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_pub_checker,
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
        def fetch_latest_version_via_pub_checker
          pub_checker = pub_update_checker
          return nil unless pub_checker

          latest = pub_checker.latest_version
          Dependabot.logger.info("Pub UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue Dependabot::DependabotError, Excon::Error => e
          Dependabot.logger.debug("Error checking Dart package #{package_name}: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def pub_update_checker
          @pub_update_checker ||= T.let(
            build_pub_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_pub_update_checker
          pub_dependency = build_pub_dependency
          return nil unless pub_dependency

          Dependabot.logger.info("Delegating to pub UpdateChecker for package: #{pub_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("pub").new(
            dependency: pub_dependency,
            dependency_files: build_pub_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_pub_dependency
          return nil unless package_name

          version = current_version || extract_version_from_requirement

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: version ? "^#{version}" : nil,
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: nil
            }],
            package_manager: "pub"
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          version_part = req_string.to_s.sub(/\A(?:[~^]|[><=]+)\s*/, "")
          return version_part if Dependabot::Pub::Version.correct?(version_part)

          nil
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_pub_dependency_files
          version = current_version || extract_version_from_requirement
          requirement = version ? "^#{version}" : "any"

          pubspec_content = <<~YAML
            name: dependabot_pre_commit_check
            version: 0.0.1
            environment:
              sdk: ">=3.0.0 <4.0.0"
            dependencies:
              #{T.must(package_name)}: #{requirement}
          YAML

          [
            Dependabot::DependencyFile.new(
              name: "pubspec.yaml",
              content: pubspec_content
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
          base = "#{base}:#{requirement}" if requirement
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
  "dart",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Dart
)
