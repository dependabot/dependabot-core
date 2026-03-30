# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater/package_json_updater"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PackageJsonUpdater
        class PnpmOverrideHelper
          extend T::Sig

          sig do
            params(
              package_json_content: String,
              dependency: Dependabot::Dependency,
              detected_package_manager: T.nilable(String)
            ).void
          end
          def initialize(package_json_content:, dependency:, detected_package_manager:)
            @package_json_content = package_json_content
            @dependency = dependency
            @detected_package_manager = detected_package_manager
          end

          sig { returns(String) }
          def updated_content
            return package_json_content unless addable?

            parsed = JSON.parse(package_json_content)
            pnpm_section = parsed["pnpm"]
            return package_json_content if pnpm_section && !pnpm_section.is_a?(Hash)

            parsed["pnpm"] ||= {}
            overrides = parsed["pnpm"]["overrides"]
            return package_json_content if overrides && !overrides.is_a?(Hash)

            parsed["pnpm"]["overrides"] ||= {}
            parsed["pnpm"]["overrides"][dependency.name] = dependency.version

            JSON.pretty_generate(parsed) + "\n"
          rescue JSON::ParserError
            package_json_content
          end

          private

          sig { returns(String) }
          attr_reader :package_json_content

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(T.nilable(String)) }
          attr_reader :detected_package_manager

          sig { returns(T::Boolean) }
          def addable?
            parsed = JSON.parse(package_json_content)
            return false unless pnpm_project?(parsed)
            return false unless existing_override_entries(parsed).is_a?(Hash)

            existing_override_entries(parsed).keys.none? do |key|
              key == dependency.name || key.end_with?("/#{dependency.name}")
            end
          rescue JSON::ParserError
            false
          end

          sig { params(parsed: T::Hash[String, T.untyped]).returns(T.untyped) }
          def existing_override_entries(parsed)
            parsed["resolutions"] ||
              parsed["overrides"] ||
              parsed.dig("pnpm", "overrides") ||
              {}
          end

          sig { params(parsed: T::Hash[String, T.untyped]).returns(T::Boolean) }
          def pnpm_project?(parsed)
            return true if detected_package_manager == "pnpm"

            package_manager = parsed["packageManager"]
            return true if package_manager.is_a?(String) && package_manager.start_with?("pnpm@")

            parsed["pnpm"].is_a?(Hash)
          end
        end
      end
    end
  end
end
