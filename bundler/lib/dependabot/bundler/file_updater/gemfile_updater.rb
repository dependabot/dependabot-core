# typed: strict
# frozen_string_literal: true

require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GemfileUpdater
        extend T::Sig

        GEMFILE_FILENAMES = %w(Gemfile gems.rb).freeze

        require_relative "git_pin_replacer"
        require_relative "git_source_remover"
        require_relative "requirement_replacer"

        sig { params(dependencies: T::Array[Dependabot::Dependency], gemfile: Dependabot::DependencyFile).void }
        def initialize(dependencies:, gemfile:)
          @dependencies = dependencies
          @gemfile = gemfile
        end

        sig { returns(String) }
        def updated_gemfile_content
          content = T.must(gemfile.content)

          dependencies.each do |dependency|
            content = replace_gemfile_version_requirement(
              dependency,
              gemfile,
              content
            )

            content = remove_gemfile_git_source(dependency, content) if remove_git_source?(dependency)

            content = update_gemfile_git_pin(dependency, gemfile, content) if update_git_pin?(dependency, gemfile)
          end

          content
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :gemfile

        sig do
          params(dependency: Dependabot::Dependency, file: Dependabot::DependencyFile, content: String).returns(String)
        end
        def replace_gemfile_version_requirement(dependency, file, content)
          return content unless requirement_changed?(file, dependency)

          updated_requirement =
            dependency.requirements
                      .find { |r| r[:file] == file.name }
                      &.fetch(:requirement)

          previous_requirement =
            dependency.previous_requirements
                      &.find { |r| r[:file] == file.name }
                      &.fetch(:requirement)

          RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemfile,
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

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def remove_git_source?(dependency)
          old_gemfile_req =
            dependency.previous_requirements
                      &.find { |f| GEMFILE_FILENAMES.include?(f[:file]) }

          return false unless old_gemfile_req&.dig(:source, :type) == "git"

          new_gemfile_req =
            dependency.requirements
                      .find { |f| GEMFILE_FILENAMES.include?(f[:file]) }

          T.must(new_gemfile_req)[:source].nil?
        end

        sig { params(dependency: Dependabot::Dependency, file: Dependabot::DependencyFile).returns(T::Boolean) }
        def update_git_pin?(dependency, file)
          new_gemfile_req =
            dependency.requirements
                      .find { |f| f[:file] == file.name }
          return false unless new_gemfile_req&.dig(:source, :type) == "git"

          # If the new requirement is a git dependency with a ref then there's
          # no harm in doing an update
          !T.must(new_gemfile_req).dig(:source, :ref).nil?
        end

        sig { params(dependency: Dependabot::Dependency, content: String).returns(String) }
        def remove_gemfile_git_source(dependency, content)
          GitSourceRemover.new(dependency: dependency).rewrite(content)
        end

        sig do
          params(dependency: Dependabot::Dependency, file: Dependabot::DependencyFile, content: String).returns(String)
        end
        def update_gemfile_git_pin(dependency, file, content)
          new_pin =
            dependency.requirements
                      .find { |f| f[:file] == file.name }
                      &.fetch(:source)
                      &.fetch(:ref)

          GitPinReplacer
            .new(dependency: dependency, new_pin: new_pin)
            .rewrite(content)
        end
      end
    end
  end
end
