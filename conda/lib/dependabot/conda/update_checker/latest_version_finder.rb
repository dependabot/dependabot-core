# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/package/package_latest_version_finder"
require "dependabot/package/package_release"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/dependency"
require "dependabot/conda/conda_registry_client"
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
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          raise_on_ignored:,
          security_advisories:,
          cooldown_options:
        )
          @raise_on_ignored = T.let(raise_on_ignored, T::Boolean)
          @cooldown_options = T.let(cooldown_options, T.nilable(Dependabot::Package::ReleaseCooldownOptions))
          @conda_client = T.let(CondaRegistryClient.new, CondaRegistryClient)

          super
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= if pip_dependency?
                                 python_latest_version_finder.package_details
                               else
                                 conda_package_details
                               end
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        private

        sig { returns(T::Boolean) }
        def pip_dependency?
          dependency.requirements.any? { |req| req[:groups]&.include?("pip") }
        end

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def conda_package_details
          channels_to_search.each do |channel|
            versions = @conda_client.available_versions(dependency.name, channel)
            next if versions.empty?

            releases = versions.map.with_index do |version, index|
              Dependabot::Package::PackageRelease.new(
                version: version,
                url: "https://anaconda.org/#{channel}/#{dependency.name}",
                latest: index.zero?
              )
            end

            return Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases
            )
          end

          nil
        end

        sig { returns(T::Array[String]) }
        def channels_to_search
          channels = []

          # Priority 1: Explicit source channel
          source_channel = extract_channel_from_source
          channels << source_channel if source_channel

          # Priority 2: Channel prefix in requirement
          requirement_channel = extract_channel_from_requirement
          channels << requirement_channel if requirement_channel && !channels.include?(requirement_channel)

          # Priority 3: Environment file channels
          env_channels = extract_all_channels_from_environment_file
          env_channels.each do |ch|
            channels << ch unless channels.include?(ch)
          end

          # Priority 4: Default fallback channels
          [CondaRegistryClient::DEFAULT_CHANNEL, "conda-forge", "main"].each do |ch|
            channels << ch unless channels.include?(ch)
          end

          channels
        end

        sig { returns(T.nilable(String)) }
        def extract_channel_from_source
          return nil unless dependency.requirements.first

          source = T.let(T.must(dependency.requirements.first)[:source], T.nilable(T::Hash[Symbol, T.untyped]))
          return nil unless source

          channel = source[:channel]
          return nil unless channel.is_a?(String)
          return nil unless CondaRegistryClient::SUPPORTED_CHANNELS.include?(channel)

          channel
        end

        sig { returns(T.nilable(String)) }
        def extract_channel_from_requirement
          dependency.requirements.each do |req|
            requirement_string = req[:requirement]
            next unless requirement_string&.include?("::")

            channel = requirement_string.split("::").first
            next unless channel
            next unless CondaRegistryClient::SUPPORTED_CHANNELS.include?(channel)

            return channel
          end

          nil
        end

        sig { returns(T::Array[String]) }
        def extract_all_channels_from_environment_file
          environment_file = dependency_files.find { |f| f.name.match?(/environment\.ya?ml/i) }
          return [] unless environment_file

          parsed = YAML.safe_load(T.must(environment_file.content))
          return [] unless parsed.is_a?(Hash)

          channels = parsed["channels"]
          return [] unless channels.is_a?(Array)

          channels.select { |ch| ch.is_a?(String) && CondaRegistryClient::SUPPORTED_CHANNELS.include?(ch) }
        rescue Psych::SyntaxError
          []
        end

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
          Dependabot::Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirements: python_compatible_requirements,
            package_manager: "pip"
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
            python_vulnerable_versions = advisory.vulnerable_versions.flat_map do |conda_req|
              Dependabot::Python::Requirement.requirements_array(conda_req.to_s)
            end

            python_safe_versions = advisory.safe_versions.flat_map do |conda_req|
              Dependabot::Python::Requirement.requirements_array(conda_req.to_s)
            end

            Dependabot::SecurityAdvisory.new(
              dependency_name: advisory.dependency_name,
              package_manager: "pip",
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
