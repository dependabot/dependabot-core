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
      class Rust < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_cargo_checker,
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
              cli: original_source[:extras] == "cli"
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
        def fetch_latest_version_via_cargo_checker
          cargo_checker = cargo_update_checker
          return nil unless cargo_checker

          latest = cargo_checker.latest_version
          Dependabot.logger.info("Cargo UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue Dependabot::DependabotError, Excon::Error, JSON::ParserError => e
          Dependabot.logger.debug("Error checking Rust package #{package_name}: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def cargo_update_checker
          @cargo_update_checker ||= T.let(
            build_cargo_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_cargo_update_checker
          cargo_dependency = build_cargo_dependency
          return nil unless cargo_dependency

          Dependabot.logger.info("Delegating to cargo UpdateChecker for package: #{cargo_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("cargo").new(
            dependency: cargo_dependency,
            dependency_files: build_cargo_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_cargo_dependency
          return nil unless package_name

          version = current_version || extract_version_from_requirement

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: version ? "=#{version}" : nil,
              groups: ["dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          version_part = req_string.sub(/\A(?:[~^]|[><=]+)\s*/, "")
          return version_part if version_part.match?(/\A\d+(?:\.\d+)*(?:-[\w.]+)?(?:\+[\w.]+)?\z/)

          nil
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_cargo_dependency_files
          version = current_version || extract_version_from_requirement
          requirement = version ? "=#{version}" : "*"

          toml_content = <<~TOML
            [package]
            name = "dependabot-pre-commit-check"
            version = "0.0.1"
            edition = "2021"

            [dependencies]
            #{T.must(package_name)} = "#{requirement}"
          TOML

          [
            Dependabot::DependencyFile.new(
              name: "Cargo.toml",
              content: toml_content
            )
          ]
        end

        sig do
          params(
            package_name: T.nilable(String),
            requirement: T.nilable(String),
            cli: T::Boolean
          ).returns(String)
        end
        def build_original_string(package_name:, requirement:, cli:)
          base = cli ? "cli:#{package_name}" : package_name.to_s
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
  "rust",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Rust
)
