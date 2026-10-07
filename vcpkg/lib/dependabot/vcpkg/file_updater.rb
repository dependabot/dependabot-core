# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/vcpkg"
require "dependabot/vcpkg/manifest_baseline"
require "dependabot/vcpkg/manifest_document"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        # Handle vcpkg.json
        vcpkg_json_file = get_original_file(VCPKG_JSON_FILENAME)
        if vcpkg_json_file && rewrite?(vcpkg_json_file)
          updated_files << updated_file(
            file: vcpkg_json_file,
            content: updated_vcpkg_json_content(vcpkg_json_file)
          )
        end

        # Handle vcpkg-configuration.json
        vcpkg_config_file = get_original_file(VCPKG_CONFIGURATION_JSON_FILENAME)
        if vcpkg_config_file && rewrite?(vcpkg_config_file)
          updated_files << updated_file(
            file: vcpkg_config_file,
            content: updated_vcpkg_configuration_json_content(vcpkg_config_file)
          )
        end

        updated_files
      end

      private

      # A security fix can move the baseline in a file that none of the updated dependencies
      # declare a requirement against, so that file needs rewriting even though `file_changed?`
      # says otherwise.
      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def rewrite?(file)
        file_changed?(file) || security_baseline&.fetch(:file) == file.name
      end

      sig { override.void }
      def check_required_files
        return if get_original_file(VCPKG_JSON_FILENAME) || get_original_file(VCPKG_CONFIGURATION_JSON_FILENAME)

        raise Dependabot::DependencyFileNotFound.new(nil, "No vcpkg manifest files found")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_vcpkg_json_content(file)
        document = ManifestDocument.from_file(file)

        dependencies
          .filter_map { |dep| [dep, dep.requirements.find { |requirement| requirement.file == file.name }] }
          .select { |_, requirement| requirement }
          .each { |dependency, _| update_dependency_in_content(document, dependency, file.name) }

        apply_security_baseline(document, file.name)

        document.content
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_vcpkg_configuration_json_content(file)
        document = ManifestDocument.from_file(file)

        dependencies
          .filter_map { |dep| [dep, dep.requirements.find { |requirement| requirement.file == file.name }] }
          .select { |_, requirement| requirement }
          .each { |dependency, _| update_registry_dependency_in_content(document, dependency, file.name) }

        apply_security_baseline(document, file.name)

        document.content
      end

      sig { params(document: ManifestDocument, dependency: Dependabot::Dependency, filename: String).void }
      def update_dependency_in_content(document, dependency, filename)
        case dependency.name
        when VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME
          baseline = baseline_for(dependency, filename)
          document.set_baseline(path: [VCPKG_BUILTIN_BASELINE_KEY], baseline: baseline) if baseline
        else
          update_port_dependency_in_content(document, dependency, filename)
        end
      end

      sig { params(document: ManifestDocument, dependency: Dependabot::Dependency, filename: String).void }
      def update_port_dependency_in_content(document, dependency, filename)
        case remediation_for(dependency, filename)
        when :override then document.set_override(name: dependency.name, version: dependency.version)
        # A baseline bump moves the port's version floor, so the port entry needs no change.
        when :baseline then nil
        else document.set_port_version(name: dependency.name, version: dependency.version)
        end
      end

      sig do
        params(dependency: Dependabot::Dependency, filename: String).returns(T.nilable(Symbol))
      end
      def remediation_for(dependency, filename)
        dependency.requirements
                  .find { |requirement| requirement.file == filename }
                  &.metadata_symbol("security_remediation")
      end

      # Where the fix wants the registry baseline moved to, if anywhere.
      sig { returns(T.nilable(T::Hash[Symbol, String])) }
      def security_baseline
        return @security_baseline if @looked_up_security_baseline

        @looked_up_security_baseline = T.let(true, T.nilable(T::Boolean))
        @security_baseline = T.let(build_security_baseline, T.nilable(T::Hash[Symbol, String]))
      end

      sig { returns(T.nilable(T::Hash[Symbol, String])) }
      def build_security_baseline
        commit_sha = dependencies
                     .flat_map(&:requirements)
                     .filter_map { |requirement| requirement.metadata_string("baseline_commit_sha") }
                     .first
        return nil unless commit_sha.is_a?(String)

        location = manifest_baseline.location
        return nil unless location

        { file: location.first, commit_sha: }
      end

      sig { params(document: ManifestDocument, filename: String).void }
      def apply_security_baseline(document, filename)
        baseline = security_baseline
        return unless baseline && baseline[:file] == filename

        document.set_baseline(path: T.must(manifest_baseline.location).last, baseline: baseline.fetch(:commit_sha))
      end

      sig { returns(Dependabot::Vcpkg::ManifestBaseline) }
      def manifest_baseline
        @manifest_baseline ||= T.let(
          Dependabot::Vcpkg::ManifestBaseline.new(dependency_files:),
          T.nilable(Dependabot::Vcpkg::ManifestBaseline)
        )
      end

      sig { params(document: ManifestDocument, dependency: Dependabot::Dependency, filename: String).void }
      def update_registry_dependency_in_content(document, dependency, filename)
        baseline = baseline_for(dependency, filename)
        return unless baseline

        if dependency.metadata[:default]
          document.set_default_registry_baseline(
            baseline: baseline, create: !!dependency.metadata[:create_default_registry]
          )
        else
          document.set_registry_baseline(
            baseline: baseline,
            repository: dependency.requirements.first&.source_string("url"),
            builtin: !!dependency.metadata[:builtin]
          )
        end
      end

      sig { params(dependency: Dependabot::Dependency, filename: String).returns(T.nilable(String)) }
      def baseline_for(dependency, filename)
        dependency.requirements.find { |candidate| candidate.file == filename }&.source_string("ref")
      end
    end
  end
end

Dependabot::FileUpdaters.register("vcpkg", Dependabot::Vcpkg::FileUpdater)
