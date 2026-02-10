# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/update_checkers"
require "dependabot/requirements_update_strategy"
require "dependabot/python/update_checker/requirements_updater"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Python < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_pip_checker,
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
              original_name: original_source[:original_name] || original_source[:package_name],
              extras: original_source[:extras],
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
        def fetch_latest_version_via_pip_checker
          pip_checker = pip_update_checker
          return nil unless pip_checker

          latest = pip_checker.latest_version
          Dependabot.logger.info("Python UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue Dependabot::PrivateSourceTimedOut,
               Dependabot::PrivateSourceAuthenticationFailure,
               Dependabot::DependencyFileNotResolvable,
               Dependabot::DependencyNotFound,
               Excon::Error::Timeout,
               Excon::Error::Socket => e
          Dependabot.logger.warn("Error checking Python package: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def pip_update_checker
          @pip_update_checker ||= T.let(
            build_pip_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_pip_update_checker
          pip_dependency = build_pip_dependency
          return nil unless pip_dependency

          Dependabot.logger.info("Delegating to Python UpdateChecker for package: #{pip_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("pip").new(
            dependency: pip_dependency,
            dependency_files: build_pip_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_pip_dependency
          return nil unless package_name

          version = current_version || extract_version_from_requirement

          # Force :requirements resolver instead of subdependency_resolver
          exact_requirement = version ? "==#{version}" : nil

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: exact_requirement,
              groups: [],
              file: "requirements.txt",
              source: nil
            }],
            package_manager: "pip"
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          match = req_string.match(/[\d]+(?:\.[\d]+)*(?:\.?\w+)*/)
          match&.[](0)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_pip_dependency_files
          version = current_version || extract_version_from_requirement
          exact_requirement = version ? "==#{version}" : ""
          content = "#{package_name}#{exact_requirement}\n"

          [
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: content
            )
          ]
        end

        sig do
          params(
            original_name: T.nilable(String),
            extras: T.nilable(String),
            requirement: T.nilable(String)
          ).returns(String)
        end
        def build_original_string(original_name:, extras:, requirement:)
          base = original_name.to_s
          base = "#{base}[#{extras}]" if extras
          base = "#{base}#{requirement}" if requirement
          base
        end

        sig { params(original_requirement: T.nilable(String), new_version: String).returns(T.nilable(String)) }
        def build_updated_requirement(original_requirement, new_version)
          return ">=#{new_version}" unless original_requirement

          updater = Dependabot::Python::UpdateChecker::RequirementsUpdater.new(
            requirements: [{
              requirement: original_requirement,
              file: "requirements.txt",
              groups: [],
              source: nil
            }],
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions,
            has_lockfile: false,
            latest_resolvable_version: new_version
          )

          updated_reqs = updater.updated_requirements
          updated_req = updated_reqs.first&.fetch(:requirement, nil)

          return ">=#{new_version}" if updated_req == :unfixable

          if updated_req == original_requirement
            force_bump_lower_bounds(original_requirement, new_version)
          else
            updated_req || ">=#{new_version}"
          end
        end

        sig { params(requirement: String, new_version: String).returns(String) }
        def force_bump_lower_bounds(requirement, new_version)
          constraints = requirement.split(",").map(&:strip)

          updated = constraints.map do |constraint|
            if constraint.match?(/\A(>=|>|~=)/)
              operator = T.must(constraint.match(/\A(>=|>|~=)/))[1]
              "#{operator}#{new_version}"
            else
              constraint
            end
          end

          updated.join(",")
        end
      end
    end
  end
end

Dependabot::PreCommit::AdditionalDependencyCheckers.register(
  "python",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Python
)
