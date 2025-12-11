# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"
require "dependabot/errors"
require "dependabot/crystal_shards/file_updater"

module Dependabot
  module CrystalShards
    class FileUpdater
      class ManifestUpdater
        extend T::Sig

        DEPENDENCY_TYPES = %w(dependencies development_dependencies).freeze

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            manifest: Dependabot::DependencyFile
          ).void
        end
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        sig { returns(String) }
        def updated_manifest_content
          content = manifest.content
          raise Dependabot::DependencyFileNotParseable, manifest.name unless content

          content = content.dup

          dependencies.each do |dep|
            content = update_dependency_version(content, dep)
            content = update_dependency_source(content, dep)
          end

          content
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_dependency_version(content, dependency)
          return content unless dependency.requirements.any? { |r| r[:requirement] }

          requirements = find_requirements_for_manifest(dependency)
          return content unless requirements

          new_requirement, old_requirement = requirements
          return content if new_requirement == old_requirement

          update_version_requirement(content, dependency.name, old_requirement, new_requirement)
        end

        sig do
          params(dependency: Dependabot::Dependency)
            .returns(T.nilable([String, String]))
        end
        def find_requirements_for_manifest(dependency)
          req = dependency.requirements.find { |r| r[:file] == manifest.name }
          return nil unless req

          old_req = dependency.previous_requirements&.find { |r| r[:file] == manifest.name }
          return nil unless old_req

          new_requirement = req[:requirement]
          old_requirement = old_req[:requirement]
          return nil unless new_requirement && old_requirement

          [new_requirement, old_requirement]
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_dependency_source(content, dependency)
          req = dependency.requirements.find { |r| r[:file] == manifest.name }
          return content unless req

          old_req = dependency.previous_requirements&.find { |r| r[:file] == manifest.name }
          return content unless old_req

          new_source = req[:source]
          old_source = old_req[:source]

          return content unless new_source && old_source
          return content if new_source == old_source

          update_git_ref(content, dependency.name, old_source, new_source)
        end

        sig do
          params(
            content: String,
            dep_name: String,
            old_requirement: String,
            new_requirement: String
          ).returns(String)
        end
        def update_version_requirement(content, dep_name, old_requirement, new_requirement)
          DEPENDENCY_TYPES.each do |dep_type|
            pattern = dependency_pattern(dep_name, dep_type)
            content = content.gsub(pattern) do |match|
              match.gsub(
                /version:\s*["']?#{Regexp.escape(old_requirement)}["']?/,
                "version: #{quote_if_needed(new_requirement)}"
              )
            end
          end

          content
        end

        sig do
          params(
            content: String,
            dep_name: String,
            old_source: T::Hash[Symbol, T.untyped],
            new_source: T::Hash[Symbol, T.untyped]
          ).returns(String)
        end
        def update_git_ref(content, dep_name, old_source, new_source)
          old_ref = old_source[:ref]
          new_ref = new_source[:ref]

          return content unless old_ref && new_ref && old_ref != new_ref

          DEPENDENCY_TYPES.each do |dep_type|
            pattern = dependency_pattern(dep_name, dep_type)
            content = content.gsub(pattern) do |match|
              match
                .gsub(/tag:\s*["']?#{Regexp.escape(old_ref.to_s)}["']?/,
                      "tag: #{quote_if_needed(new_ref.to_s)}")
                .gsub(/commit:\s*["']?#{Regexp.escape(old_ref.to_s)}["']?/,
                      "commit: #{quote_if_needed(new_ref.to_s)}")
            end
          end

          content
        end

        sig { params(dep_name: String, dep_type: String).returns(Regexp) }
        def dependency_pattern(dep_name, dep_type)
          /#{Regexp.escape(dep_type)}:\s*\n(?:.*\n)*?\s+#{Regexp.escape(dep_name)}:\s*\n(?:\s+[^\n]+\n)*/m
        end

        sig { params(value: String).returns(String) }
        def quote_if_needed(value)
          if value.match?(/^[\d.]+$/) || value.match?(/^[a-zA-Z0-9._-]+$/)
            value
          else
            "\"#{value}\""
          end
        end
      end
    end
  end
end
