# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class GemfileUpdater
          require_relative "git_pin_replacer"
          require_relative "git_source_remover"
          require_relative "requirement_replacer"

          LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
          GIT_DEPENDENCIES_SECTION = /GIT\n.*?\n\n(?!GIT)/m
          GIT_DEPENDENCY_DETAILS = /GIT\n.*?\n\n/m
          GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/
          GEMSPEC_SOURCES = [
            ::Bundler::Source::Path,
            ::Bundler::Source::Gemspec
          ].freeze
          RETRYABLE_ERRORS = [::Bundler::HTTPError].freeze

          def initialize(dependencies:, gemfile:)
            @dependencies = dependencies
            @gemfile = gemfile
          end

          def updated_gemfile_content
            content = gemfile.content

            dependencies.each do |dependency|
              content = replace_gemfile_version_requirement(
                dependency,
                gemfile,
                content
              )

              if remove_git_source?(dependency)
                content = remove_gemfile_git_source(dependency, content)
              end

              if update_git_pin?(dependency)
                content = update_gemfile_git_pin(dependency, gemfile, content)
              end
            end

            content
          end

          private

          attr_reader :dependencies, :gemfile

          def replace_gemfile_version_requirement(dependency, file, content)
            return content unless requirement_changed?(file, dependency)

            updated_requirement =
              dependency.requirements.
              find { |r| r[:file] == file.name }.
              fetch(:requirement)

            RequirementReplacer.new(
              dependency: dependency,
              file_type: :gemfile,
              updated_requirement: updated_requirement
            ).rewrite(content)
          end

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end

          def remove_git_source?(dependency)
            old_gemfile_req =
              dependency.previous_requirements.
              find { |f| f[:file] == "Gemfile" }

            return false unless old_gemfile_req&.dig(:source, :type) == "git"

            new_gemfile_req =
              dependency.requirements.find { |f| f[:file] == "Gemfile" }

            new_gemfile_req[:source].nil?
          end

          def update_git_pin?(dependency)
            new_gemfile_req =
              dependency.requirements.find { |f| f[:file] == "Gemfile" }
            return false unless new_gemfile_req&.dig(:source, :type) == "git"

            # If the new requirement is a git dependency with a ref then there's
            # no harm in doing an update
            new_gemfile_req.dig(:source, :ref)
          end

          def remove_gemfile_git_source(dependency, content)
            GitSourceRemover.new(dependency: dependency).rewrite(content)
          end

          def update_gemfile_git_pin(dependency, file, content)
            new_pin =
              dependency.requirements.
              find { |f| f[:file] == file.name }.
              fetch(:source).fetch(:ref)

            GitPinReplacer.
              new(dependency: dependency, new_pin: new_pin).
              rewrite(content)
          end
        end
      end
    end
  end
end
