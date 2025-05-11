# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

require "dependabot/azure_pipelines/constants"
require "dependabot/azure_pipelines/package_manager"

module Dependabot
  module AzurePipelines
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files
          .select(&:content)
          .flat_map { |dependency_file| parse_dependency_file(dependency_file) }
          .each { |dependency| dependency_set << dependency }

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_dependency_file(dependency_file)
        return [] unless dependency_file.content

        contents = begin
          YAML.safe_load(T.must(dependency_file.content), symbolize_names: true)
        rescue Psych::SyntaxError => _e
          raise Dependabot::DependencyFileNotParseable, dependency_file.path
        end

        return [] unless contents.is_a?(Hash)

        case contents
        in {stages: stages} then stages.flat_map { |stage| parse_stage(stage, dependency_file.path) }
        in {jobs: jobs} then jobs.flat_map { |job| parse_job(job, dependency_file.path) }
        in {steps: steps} then steps.filter_map { |step| parse_step(step, dependency_file.path) }
        else raise Dependabot::DependencyFileNotParseable, dependency_file.path
        end
      end

      sig { params(stage: T::Hash[Symbol, T.untyped], file: String).returns(T::Array[Dependabot::Dependency]) }
      def parse_stage(stage, file)
        return [] unless stage.is_a?(Hash)

        stage[:jobs].flat_map { |job| parse_job(job, file) }
      end

      sig { params(job: T::Hash[Symbol, T.untyped], file: String).returns(T::Array[Dependabot::Dependency]) }
      def parse_job(job, file)
        return [] unless job.is_a?(Hash)

        job[:steps].filter_map { |step| parse_step(step, file) }
      end

      sig { params(step: T::Hash[Symbol, T.untyped], file: String).returns(T.nilable(Dependabot::Dependency)) }
      def parse_step(step, file)
        task = step[:task]
        return unless task.is_a?(String)

        task_name, task_version = task.split("@", 2)
        return unless task_name && task_version && !task_name.empty? && !task_version.empty?

        Dependabot::Dependency.new(
          name: task_name,
          version: task_version,
          package_manager: "azure_pipelines",
          requirements: [{
            file: file,
            requirement: task_version,
            groups: [],
            source: nil
          }],
          metadata: parse_version(task_version)
        )
      rescue StandardError => e
        raise Dependabot::DependencyFileNotParseable, "Error parsing step: #{e.message}"
      end

      # We want to retain the specific version format used in Azure Pipelines,
      # so that when we propose an update later, we retain the same format.
      # For example, if only the major version is specified, we want to keep it that way.
      sig { params(version: String).returns(T.nilable(T::Hash[Symbol, Integer])) }
      def parse_version(version)
        return nil unless version.is_a?(String)

        match = version.match(/^(\d+)(?:\.(\d+)(?:\.(\d+))?)?$/)
        return nil unless match

        result = {}
        result[:major] = Integer(match[1]) if match[1]
        result[:minor] = Integer(match[2]) if match[2]
        result[:patch] = Integer(match[3]) if match[3]

        result.empty? ? nil : result
      rescue StandardError => e
        raise Dependabot::DependencyFileNotParseable, "Error parsing version: #{e.message}"
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        PackageManager.new
      end
    end
  end
end

Dependabot::FileParsers.register("azure_pipelines", Dependabot::AzurePipelines::FileParser)
