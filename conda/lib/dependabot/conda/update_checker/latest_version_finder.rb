# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package/package_latest_version_finder"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/dependency"
require_relative "requirement_translator"

module Dependabot
  module Conda
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored:, security_advisories:,
                       cooldown_options:)
          @raise_on_ignored = T.let(raise_on_ignored, T::Boolean)
          @cooldown_options = T.let(cooldown_options, T.nilable(Dependabot::Package::ReleaseCooldownOptions))

          super
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= python_latest_version_finder.package_details
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        private

        sig { returns(Dependabot::Python::UpdateChecker::LatestVersionFinder) }
        def python_latest_version_finder
          @python_latest_version_finder ||= T.let(
            Dependabot::Python::UpdateChecker::LatestVersionFinder.new(
              dependency: python_compatible_dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: @raise_on_ignored,
              security_advisories: python_compatible_security_advisories,
              cooldown_options: @cooldown_options
            ),
            T.nilable(Dependabot::Python::UpdateChecker::LatestVersionFinder)
          )
        end

        sig { returns(Dependabot::Dependency) }
        def python_compatible_dependency
          # Convert conda dependency to python-compatible dependency
          Dependabot::Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirements: python_compatible_requirements,
            package_manager: "pip" # Use pip for PyPI compatibility
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def python_compatible_requirements
          dependency.requirements.map do |req|
            req.merge(
              requirement: convert_conda_requirement_to_pip(req[:requirement])
            )
          end
        end

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        def python_compatible_security_advisories
          security_advisories.map do |advisory|
            # Convert Conda requirements to Python requirements for pip compatibility
            python_vulnerable_versions = advisory.vulnerable_versions.flat_map do |conda_req|
              Dependabot::Python::Requirement.requirements_array(conda_req.to_s)
            end

            python_safe_versions = advisory.safe_versions.flat_map do |conda_req|
              Dependabot::Python::Requirement.requirements_array(conda_req.to_s)
            end

            # Normalize security advisories to use 'pip' package manager for Python delegation
            Dependabot::SecurityAdvisory.new(
              dependency_name: advisory.dependency_name,
              package_manager: "pip", # Use pip for PyPI compatibility
              vulnerable_versions: python_vulnerable_versions,
              safe_versions: python_safe_versions
            )
          end
        end

        sig { params(conda_requirement: T.nilable(String)).returns(T.nilable(String)) }
        def convert_conda_requirement_to_pip(conda_requirement)
          RequirementTranslator.conda_to_pip(conda_requirement)
        end
      end
    end
  end
end
