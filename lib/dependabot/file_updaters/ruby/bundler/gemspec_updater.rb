# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class GemspecUpdater
          require_relative "requirement_replacer"

          def initialize(dependencies:, gemspec:)
            @dependencies = dependencies
            @gemspec = gemspec
          end

          def updated_gemspec_content
            content = gemspec.content

            dependencies.each do |dependency|
              content = replace_gemspec_version_requirement(
                gemspec, dependency, content
              )
            end

            content
          end

          private

          attr_reader :dependencies, :gemspec

          def replace_gemspec_version_requirement(gemspec, dependency, content)
            return content unless requirement_changed?(gemspec, dependency)

            updated_requirement =
              dependency.requirements.
              find { |r| r[:file] == gemspec.name }.
              fetch(:requirement)

            previous_requirement =
              dependency.previous_requirements.
              find { |r| r[:file] == gemspec.name }.
              fetch(:requirement)

            RequirementReplacer.new(
              dependency: dependency,
              file_type: :gemspec,
              updated_requirement: updated_requirement,
              previous_requirement: previous_requirement
            ).rewrite(content)
          end

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end
        end
      end
    end
  end
end
