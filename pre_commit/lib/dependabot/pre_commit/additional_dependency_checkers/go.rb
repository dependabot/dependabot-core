# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/update_checkers"
require "dependabot/go_modules/version"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Go < Base
        extend T::Sig

        sig { override.returns(T.nilable(String)) }
        def latest_version
          return nil unless package_name

          @latest_version ||= T.let(
            fetch_latest_version_via_go_checker,
            T.nilable(String)
          )
        end

        sig { override.params(latest_version: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(latest_version)
          requirements.map do |original_req|
            original_source = original_req[:source]
            next original_req unless original_source.is_a?(Hash)
            next original_req unless original_source[:type] == "additional_dependency"

            new_requirement = "v#{latest_version}"

            new_original_string = build_original_string(
              original_name: original_source[:original_name] || original_source[:package_name],
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
        def fetch_latest_version_via_go_checker
          go_checker = go_update_checker
          return nil unless go_checker

          latest = go_checker.latest_version
          Dependabot.logger.info("Go UpdateChecker found latest version: #{latest || 'none'}")

          latest&.to_s
        rescue Dependabot::PrivateSourceTimedOut,
               Dependabot::PrivateSourceAuthenticationFailure,
               Dependabot::DependencyFileNotResolvable,
               Dependabot::DependencyNotFound,
               Excon::Error::Timeout,
               Excon::Error::Socket => e
          Dependabot.logger.warn("Error checking Go module: #{e.message}")
          nil
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def go_update_checker
          @go_update_checker ||= T.let(
            build_go_update_checker,
            T.nilable(Dependabot::UpdateCheckers::Base)
          )
        end

        sig { returns(T.nilable(Dependabot::UpdateCheckers::Base)) }
        def build_go_update_checker
          go_dependency = build_go_dependency
          return nil unless go_dependency

          Dependabot.logger.info("Delegating to Go UpdateChecker for module: #{go_dependency.name}")

          Dependabot::UpdateCheckers.for_package_manager("go_modules").new(
            dependency: go_dependency,
            dependency_files: build_go_dependency_files,
            credentials: credentials,
            ignored_versions: [],
            security_advisories: [],
            raise_on_ignored: false
          )
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def build_go_dependency
          return nil unless package_name

          version = current_version || extract_version_from_requirement

          Dependabot::Dependency.new(
            name: T.must(package_name),
            version: version,
            requirements: [{
              requirement: version ? "v#{version}" : nil,
              groups: [],
              file: "go.mod",
              source: { type: "default", source: T.must(package_name) }
            }],
            package_manager: "go_modules"
          )
        end

        sig { returns(T.nilable(String)) }
        def extract_version_from_requirement
          req_string = requirements.first&.dig(:requirement)
          return nil unless req_string

          # Go versions are like "v1.2.3" — strip the leading "v"
          version = req_string.to_s.sub(/\Av/, "")
          return nil unless Dependabot::GoModules::Version.correct?(version)

          version
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def build_go_dependency_files
          version = current_version || extract_version_from_requirement
          version_string = version ? "v#{version}" : ""
          content = "module dependabot/pre-commit-dummy\n\ngo 1.21\n\nrequire #{package_name} #{version_string}\n"

          [
            Dependabot::DependencyFile.new(
              name: "go.mod",
              content: content
            )
          ]
        end

        sig do
          params(
            original_name: T.nilable(String),
            requirement: T.nilable(String)
          ).returns(String)
        end
        def build_original_string(original_name:, requirement:)
          base = original_name.to_s
          base = "#{base}@#{requirement}" if requirement
          base
        end
      end
    end
  end
end

Dependabot::PreCommit::AdditionalDependencyCheckers.register(
  "golang",
  Dependabot::PreCommit::AdditionalDependencyCheckers::Go
)
