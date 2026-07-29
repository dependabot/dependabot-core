# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/vcpkg"
require "dependabot/vcpkg/manifest_baseline"
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
        content = T.must(file.content)
        parsed_content = JSON.parse(content)

        dependencies
          .filter_map { |dep| [dep, dep.requirements.find { |r| r[:file] == file.name }] }
          .select { |_, requirement| requirement }
          .each { |dependency, _| update_dependency_in_content(parsed_content, dependency, file.name) }

        apply_security_baseline(parsed_content, file.name)

        JSON.pretty_generate(parsed_content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_vcpkg_configuration_json_content(file)
        content = T.must(file.content)
        parsed_content = JSON.parse(content)

        dependencies
          .filter_map { |dep| [dep, dep.requirements.find { |r| r[:file] == file.name }] }
          .select { |_, requirement| requirement }
          .each { |dependency, _| update_registry_dependency_in_content(parsed_content, dependency, file.name) }

        apply_security_baseline(parsed_content, file.name)

        JSON.pretty_generate(parsed_content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_dependency_in_content(content, dependency, filename)
        case dependency.name
        when VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME
          update_baseline_in_content(content, dependency, filename)
        else
          update_port_dependency_in_content(content, dependency, filename)
        end
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_baseline_in_content(content, dependency, filename)
        update_baseline_field(content, dependency, filename, VCPKG_BUILTIN_BASELINE_KEY)
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_port_dependency_in_content(content, dependency, filename)
        case remediation_for(dependency, filename)
        when :override then apply_override(content, dependency)
        # A baseline bump moves the port's version floor, so the port entry needs no change.
        when :baseline then nil
        else update_version_constraint(content, dependency)
        end
      end

      sig do
        params(dependency: Dependabot::Dependency, filename: String).returns(T.nilable(Symbol))
      end
      def remediation_for(dependency, filename)
        requirement = dependency.requirements.find { |r| r[:file] == filename }
        metadata = requirement&.dig(:metadata)
        return nil unless metadata.is_a?(Hash)

        metadata[:security_remediation]
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency).void }
      def update_version_constraint(content, dependency)
        entries = content[VCPKG_DEPENDENCIES_KEY]
        return unless entries.is_a?(Array)

        index = entries.index { |entry| port_entry_name(entry) == dependency.name }
        return unless index

        entry = entries[index]
        # A port declared as a bare string has to become an object to carry a constraint.
        entry = { "name" => entry } if entry.is_a?(String)
        return unless entry.is_a?(Hash)

        entry[VCPKG_VERSION_CONSTRAINT_KEY] = dependency.version
        entries[index] = entry
      end

      # vcpkg cannot compare versions across schemes, so when no safe version shares the current
      # one's scheme, the only way to move the port is to pin it outright. `version` is the
      # scheme-agnostic key, and the port version belongs in it as a `#N` suffix: the separate
      # `port-version` key and the scheme-specific keys are both deprecated.
      # See https://learn.microsoft.com/vcpkg/reference/vcpkg-json#overrides
      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency).void }
      def apply_override(content, dependency)
        entry = { "name" => dependency.name, "version" => dependency.version }

        overrides = content[VCPKG_OVERRIDES_KEY]
        unless overrides.is_a?(Array)
          overrides = []
          content[VCPKG_OVERRIDES_KEY] = overrides
        end

        index = overrides.index { |override| override.is_a?(Hash) && override["name"] == dependency.name }
        index ? overrides[index] = entry : overrides << entry
      end

      sig { params(entry: T.untyped).returns(T.nilable(String)) }
      def port_entry_name(entry)
        return entry if entry.is_a?(String)
        return nil unless entry.is_a?(Hash)

        name = entry["name"]
        name.is_a?(String) ? name : nil
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
                     .filter_map { |requirement| requirement.dig(:metadata, :baseline_commit_sha) }
                     .first
        return nil unless commit_sha.is_a?(String)

        location = manifest_baseline.location
        return nil unless location

        { file: location.first, commit_sha: }
      end

      sig { params(content: T::Hash[String, T.untyped], filename: String).void }
      def apply_security_baseline(content, filename)
        baseline = security_baseline
        return unless baseline && baseline[:file] == filename

        path = T.must(manifest_baseline.location).last
        key = path.last
        return unless key

        target = T.must(path[0...-1]).reduce(content) { |node, segment| node.is_a?(Hash) ? node[segment] : nil }
        return unless target.is_a?(Hash)

        target[key] = baseline[:commit_sha]
      end

      sig { returns(Dependabot::Vcpkg::ManifestBaseline) }
      def manifest_baseline
        @manifest_baseline ||= T.let(
          Dependabot::Vcpkg::ManifestBaseline.new(dependency_files:),
          T.nilable(Dependabot::Vcpkg::ManifestBaseline)
        )
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_registry_dependency_in_content(content, dependency, filename)
        # Check if this is a default registry update based on metadata
        if dependency.metadata[:default]
          update_default_registry(content, dependency, filename)
        else
          # For registries array, find by repository URL
          update_registry_by_name(content, dependency, filename)
        end
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_default_registry(content, dependency, filename)
        default_registry = content["default-registry"]
        if default_registry.is_a?(Hash)
          update_baseline_field(default_registry, dependency, filename, "baseline")
        elsif dependency.metadata[:create_default_registry]
          created_registry = build_default_registry(dependency, filename)
          content["default-registry"] = created_registry if created_registry
        end
      end

      sig do
        params(dependency: Dependabot::Dependency, filename: String)
          .returns(T.nilable(T::Hash[String, String]))
      end
      def build_default_registry(dependency, filename)
        requirement = dependency.requirements.find { |r| r[:file] == filename }
        return unless requirement

        case requirement[:source]
        in { ref: String => baseline }
          {
            "kind" => "git",
            "repository" => VCPKG_DEFAULT_REGISTRY_REPOSITORY,
            "baseline" => baseline
          }
        else
          nil
        end
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_registry_by_name(content, dependency, filename)
        registries = content["registries"]
        return unless registries.is_a?(Array)

        # Find registry based on dependency characteristics
        registry = find_target_registry(registries, dependency)
        return unless registry

        update_baseline_field(registry, dependency, filename, "baseline")
      end

      sig do
        params(
          target: T::Hash[String, T.untyped],
          dependency: Dependabot::Dependency,
          filename: String,
          field_name: String
        ).void
      end
      def update_baseline_field(target, dependency, filename, field_name)
        # Find the requirement for this specific file
        requirement = dependency.requirements.find { |r| r[:file] == filename }
        return unless requirement

        # Extract and validate the new baseline
        case requirement[:source]
        in { ref: String => new_baseline }
          target[field_name] = new_baseline
        else
          # Skip if source doesn't have the expected structure
        end
      end

      sig do
        params(
          registries: T::Array[T.untyped],
          dependency: Dependabot::Dependency
        )
          .returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def find_target_registry(registries, dependency)
        if dependency.metadata[:builtin]
          # For builtin registries, find by kind
          registries.find { |r| r.is_a?(Hash) && r["kind"] == "builtin" }
        else
          # For git registries, find by repository URL
          repository_url = dependency.requirements.first&.dig(:source, :url)
          registries.find { |r| r.is_a?(Hash) && r["repository"] == repository_url }
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("vcpkg", Dependabot::Vcpkg::FileUpdater)
