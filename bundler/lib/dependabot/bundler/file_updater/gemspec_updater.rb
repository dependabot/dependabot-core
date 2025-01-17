# typed: strict
# frozen_string_literal: true

require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GemspecUpdater
        require_relative "requirement_replacer"

        extend T::Sig

        sig { params(dependencies: T::Array[Dependabot::Dependency], gemspec: Dependabot::DependencyFile).void }
        def initialize(dependencies:, gemspec:)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @gemspec = T.let(gemspec, Dependabot::DependencyFile)
        end

        sig { returns(String) }
        def updated_gemspec_content
          content = T.let(gemspec.content, T.untyped)

          dependencies.each do |dependency|
            content = replace_gemspec_version_requirement(
              gemspec, dependency, content
            )
          end

          content
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :gemspec

        sig do
          params(gemspec: Dependabot::DependencyFile, dependency: Dependabot::Dependency,
                 content: String).returns(String)
        end
        def replace_gemspec_version_requirement(gemspec, dependency, content)
          return content unless requirement_changed?(gemspec, dependency)

          updated_requirement =
            T.must(dependency.requirements
                      .find { |r| r[:file] == gemspec.name })
             .fetch(:requirement)

          previous_requirement =
            T.must(T.must(dependency.previous_requirements)
                      .find { |r| r[:file] == gemspec.name })
             .fetch(:requirement)

          RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemspec,
            updated_requirement: updated_requirement,
            previous_requirement: previous_requirement
          ).rewrite(content)
        end

        sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - T.must(dependency.previous_requirements)

          changed_requirements.any? { |f| f[:file] == file.name }
        end
      end
    end
  end
end
