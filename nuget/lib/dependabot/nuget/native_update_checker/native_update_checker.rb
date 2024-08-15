# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/analysis/analysis_json_reader"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeUpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "native_requirements_updater"

      sig { override.returns(T.nilable(String)) }
      def latest_version
        # No need to find latest version for transitive dependencies unless they have a vulnerability.
        return dependency.version if !dependency.top_level? && !vulnerable?

        # if no update sources have the requisite package, then we can only assume that the current version is correct
        @latest_version = T.let(
          update_analysis.dependency_analysis.updated_version,
          T.nilable(String)
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # We always want a full unlock since any package update could update peer dependencies as well.
        # To force a full unlock instead of an own unlock, we return nil.
        nil
      end

      sig { override.returns(Dependabot::Nuget::Version) }
      def lowest_security_fix_version
        update_analysis.dependency_analysis.numeric_updated_version
      end

      sig { override.returns(T.nilable(Dependabot::Nuget::Version)) }
      def lowest_resolvable_security_fix_version
        return nil if version_comes_from_multi_dependency_property?

        update_analysis.dependency_analysis.numeric_updated_version
      end

      sig { override.returns(NilClass) }
      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Nuget has a single dependency file
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dep_details = updated_dependency_details.find { |d| d.name.casecmp?(dependency.name) }
        NativeRequirementsUpdater.new(
          requirements: dependency.requirements,
          dependency_details: dep_details,
          vulnerable: vulnerable?
        ).updated_requirements
      end

      sig { returns(T::Boolean) }
      def up_to_date?
        !update_analysis.dependency_analysis.can_update
      end

      sig { returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        update_analysis.dependency_analysis.can_update
      end

      sig { returns(T::Boolean) }
      def public_latest_version_resolvable_with_full_unlock?
        latest_version_resolvable_with_full_unlock?
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def public_updated_dependencies_after_full_unlock
        updated_dependencies_after_full_unlock
      end

      private

      sig { returns(AnalysisJsonReader) }
      def update_analysis
        @update_analysis ||= T.let(request_analysis, T.nilable(AnalysisJsonReader))
      end

      sig { returns(String) }
      def dependency_file_path
        File.join(NativeDiscoveryJsonReader.temp_directory, "dependency", "#{dependency.name}.json")
      end

      sig { returns(AnalysisJsonReader) }
      def request_analysis
        discovery_file_path = NativeDiscoveryJsonReader.get_discovery_file_path_from_dependency_files(dependency_files)
        analysis_folder_path = AnalysisJsonReader.temp_directory

        write_dependency_info

        NativeHelpers.run_nuget_analyze_tool(repo_root: T.must(repo_contents_path),
                                             discovery_file_path: discovery_file_path,
                                             dependency_file_path: dependency_file_path,
                                             analysis_folder_path: analysis_folder_path,
                                             credentials: credentials)

        analysis_json = AnalysisJsonReader.analysis_json(dependency_name: dependency.name)

        AnalysisJsonReader.new(analysis_json: T.must(analysis_json))
      end

      sig { void }
      def write_dependency_info
        dependency_version = T.let(dependency.requirements.first&.fetch(:requirement, nil), T.nilable(String))
        dependency_info = {
          Name: dependency.name,
          Version: dependency_version || dependency.version.to_s,
          IsVulnerable: vulnerable?,
          IgnoredVersions: ignored_versions,
          Vulnerabilities: security_advisories.map do |vulnerability|
            {
              DependencyName: vulnerability.dependency_name,
              PackageManager: vulnerability.package_manager,
              VulnerableVersions: vulnerability.vulnerable_versions.map(&:to_s),
              SafeVersions: vulnerability.safe_versions.map(&:to_s)
            }
          end
        }.to_json
        dependency_directory = File.dirname(dependency_file_path)

        begin
          Dir.mkdir(dependency_directory)
        rescue StandardError
          nil?
        end

        Dependabot.logger.info("Writing dependency info: #{dependency_info}")
        File.write(dependency_file_path, dependency_info)
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def discovered_dependencies
        discovery_json_reader = NativeDiscoveryJsonReader.get_discovery_from_dependency_files(dependency_files)
        discovery_json_reader.dependency_set(dependency_files: dependency_files, top_level_only: false)
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # We always want a full unlock since any package update could update peer dependencies as well.
        true
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/BlockLength
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        dependencies = discovered_dependencies.dependencies
        updated_dependency_details.filter_map do |dependency_details|
          dep = dependencies.find { |d| d.name.casecmp(dependency_details.name)&.zero? }
          next unless dep

          dep_metadata = T.let({}, T::Hash[Symbol, T.untyped])
          # For peer dependencies, instruct updater to not directly update this dependency
          dep_metadata[:information_only] = true unless dependency.name.casecmp(dependency_details.name)&.zero?
          dep_metadata[:is_vulnerable] = vulnerable?

          # rebuild the new requirements with the updated dependency details
          updated_reqs = dep.requirements.map do |r|
            r = r.clone
            T.let(r[:metadata], T::Hash[Symbol, T.untyped])[:previous_requirement] = r[:requirement] # keep old version
            r[:requirement] = dependency_details.version # set new version
            r[:source] = {
              type: "nuget_repo",
              source_url: dependency_details.info_url
            }
            r
          end

          reqs = dep.requirements
          unless vulnerable?
            updated_reqs = updated_reqs.filter do |r|
              req_metadata = T.let(r.fetch(:metadata, {}), T::Hash[Symbol, T.untyped])
              !T.let(req_metadata[:is_transitive], T::Boolean)
            end
            reqs = reqs.filter do |r|
              req_metadata = T.let(r.fetch(:metadata, {}), T::Hash[Symbol, T.untyped])
              !T.let(req_metadata[:is_transitive], T::Boolean)
            end
          end

          # report back the highest version that all of these dependencies can be updated to
          # this will ensure that we get a chance to update all relevant dependencies
          max_updatable_version = updated_reqs.filter_map do |r|
            v = T.let(r.fetch(:requirement, nil), T.nilable(String))
            next unless v

            Dependabot::Nuget::Version.new(v)
          end.max
          next unless max_updatable_version

          previous_version = T.let(dep.requirements.first&.fetch(:requirement, nil), T.nilable(String))
          Dependency.new(
            name: dep.name,
            version: max_updatable_version.to_s,
            requirements: updated_reqs,
            previous_version: previous_version,
            previous_requirements: reqs,
            package_manager: dep.package_manager,
            metadata: dep_metadata
          )
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/BlockLength
      # rubocop:enable Metrics/AbcSize

      sig { returns(T::Array[Dependabot::Nuget::NativeDependencyDetails]) }
      def updated_dependency_details
        @updated_dependency_details ||= T.let(update_analysis.dependency_analysis.updated_dependencies,
                                              T.nilable(T::Array[Dependabot::Nuget::NativeDependencyDetails]))
      end

      sig { returns(T::Boolean) }
      def version_comes_from_multi_dependency_property?
        update_analysis.dependency_analysis.version_comes_from_multi_dependency_property
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nuget", Dependabot::Nuget::UpdateChecker)
