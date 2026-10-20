# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "json"
require "yaml"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/requirement"

module Dependabot
  module NpmAndYarn
    class YarnBerryTransitiveUpdate
      extend T::Sig

      sig do
        params(
          dependency_name: String,
          current_version: T.nilable(String),
          target_version: String,
          lockfile_name: String,
          env: T.nilable(T::Hash[String, String])
        ).returns(T.nilable(String))
      end
      def self.updated_lockfile_content(dependency_name:, current_version:, target_version:, lockfile_name:, env: nil)
        return unless current_version

        resolutions = resolutions_for(dependency_name, current_version, target_version, lockfile_name)
        return if resolutions.empty?

        original_lockfile = T.cast(YAML.safe_load_file(lockfile_name), T::Hash[String, Object])
        original_descriptors = original_lockfile.keys.flat_map { |key| key.split(", ") }
        original_manifest = File.read("package.json")
        manifest = T.cast(JSON.parse(original_manifest), T::Hash[String, Object])
        existing_resolutions = T.cast(manifest.fetch("resolutions", {}), T::Hash[String, String])
        manifest["resolutions"] = existing_resolutions.merge(manifest_resolutions(original_lockfile, resolutions))
        File.write("package.json", JSON.generate(manifest))
        begin
          mode = Helpers.yarn_major_version == 2 ? "--skip-builds" : "--mode=skip-build"
          Helpers.run_yarn_command(
            ["install", mode],
            fingerprint: "install <no-build-mode>",
            env: (env || {}).merge("YARN_ENABLE_SCRIPTS" => "false")
          )
        ensure
          File.write("package.json", original_manifest)
        end
        restore_descriptors(lockfile_name, resolutions, original_descriptors)
        Helpers.run_yarn_command(
          ["install", mode],
          fingerprint: "install <no-build-mode>",
          env: (env || {}).merge("YARN_ENABLE_SCRIPTS" => "false")
        )
        File.read(lockfile_name)
      end

      sig do
        params(lockfile: T::Hash[String, Object], resolutions: T::Array[[String, String]])
          .returns(T::Hash[String, String])
      end
      def self.manifest_resolutions(lockfile, resolutions)
        resolutions.each_with_object(T.let({}, T::Hash[String, String])) do |(descriptor, resolution), overrides|
          name, selector = descriptor.split("@npm:", 2)
          name = T.must(name)
          unless T.must(selector).include?("/")
            overrides[descriptor] = resolution
            next
          end

          lockfile.each do |key, value|
            next if key == "__metadata"

            record = T.cast(value, T::Hash[String, Object])
            dependencies = T.cast(record.fetch("dependencies", {}), T::Hash[String, String])
            next unless dependencies[name] == "npm:#{selector}"

            overrides["#{record.fetch('resolution')}/#{name}"] = resolution
          end
        end
      end
      private_class_method :manifest_resolutions

      sig do
        params(lockfile_name: String, resolutions: T::Array[[String, String]], original_descriptors: T::Array[String]).void
      end
      def self.restore_descriptors(lockfile_name, resolutions, original_descriptors)
        replacements = resolutions.group_by do |descriptor, resolution|
          "#{descriptor.split('@npm:', 2).first}@#{resolution}"
        end
        parsed = T.cast(YAML.safe_load_file(lockfile_name), T::Hash[String, Object])
        normalized = parsed.transform_keys do |key|
          key.split(", ").flat_map do |descriptor|
            originals = replacements[descriptor]
            next [descriptor] unless originals

            restored = originals.map(&:first)
            original_descriptors.include?(descriptor) ? [descriptor, *restored] : restored
          end.uniq.sort.join(", ")
        end
        File.write(lockfile_name, T.cast(YAML.dump(normalized), String))
      end
      private_class_method :restore_descriptors

      sig do
        params(dependency_name: String, current_version: String, target_version: String, lockfile_name: String)
          .returns(T::Array[[String, String]])
      end
      def self.resolutions_for(dependency_name, current_version, target_version, lockfile_name)
        file = DependencyFile.new(name: lockfile_name, content: File.read(lockfile_name))
        targeted_descriptors(file, dependency_name, current_version).map do |descriptor|
          selector = T.must(descriptor.split("@npm:", 2).last)
          aliased_requirement = Requirement.parse_dep_string(selector)

          validate_requirement!(
            aliased_requirement ? T.must(aliased_requirement[:requirement]) : selector,
            target_version
          )
          resolution = aliased_requirement ? "npm:#{dependency_name}@#{target_version}" : "npm:#{target_version}"
          [descriptor, resolution]
        end
      end
      private_class_method :resolutions_for

      sig do
        params(file: DependencyFile, dependency_name: String, current_version: String).returns(T::Array[String])
      end
      def self.targeted_descriptors(file, dependency_name, current_version)
        FileParser::YarnLock.new(file).parsed.flat_map do |selectors, record|
          next [] unless record.version == current_version

          selectors.split(", ").select do |descriptor|
            name, selector = descriptor.split("@npm:", 2)
            next false unless selector

            (Requirement.parse_dep_string(selector)&.fetch(:name) || name) == dependency_name
          end
        end
      end
      private_class_method :targeted_descriptors

      sig do
        params(
          original: T::Array[DependencyFile], updated: T::Array[DependencyFile], dependency: Dependency
        ).returns(T.nilable(Version))
      end
      def self.resolved_version(original:, updated:, dependency:)
        current_version = dependency.version
        return unless current_version

        versions = updated.map do |file|
          previous = original.find { |candidate| candidate.name == file.name }
          next unless previous

          version_for_descriptors(previous, file, dependency.name, current_version)
        end
        versions.compact.min unless versions.any?(&:nil?)
      end

      sig { params(lockfiles: T::Array[DependencyFile]).returns(T::Boolean) }
      def self.applicable_lockfiles?(lockfiles)
        lockfiles.any? && lockfiles.all? { |file| Helpers.yarn_berry?(file) }
      end

      sig do
        params(original: DependencyFile, updated: DependencyFile, dependency_name: String, current_version: String)
          .returns(T.nilable(Version))
      end
      def self.version_for_descriptors(original, updated, dependency_name, current_version)
        descriptors = targeted_descriptors(original, dependency_name, current_version)
        records = FileParser::YarnLock.new(updated).parsed
        versions = descriptors.filter_map do |descriptor|
          record = records.find { |selectors, _| selectors.split(", ").include?(descriptor) }&.last
          Version.new(record.version) if record
        end
        versions.min if versions.length == descriptors.length
      end
      private_class_method :version_for_descriptors

      sig { params(requirement: String, target_version: String).void }
      def self.validate_requirement!(requirement, target_version)
        return if Version::VERSION_TAGS.include?(requirement)
        return if Requirement.requirements_array(requirement).any? do |range|
          range.satisfied_by?(Version.new(target_version))
        end

        raise SharedHelpers::HelperSubprocessFailed.new(
          message: "Selected Yarn version #{target_version} does not satisfy #{requirement}", error_context: {}
        )
      rescue Gem::Requirement::BadRequirementError
        nil
      end
      private_class_method :validate_requirement!
    end
  end
end
