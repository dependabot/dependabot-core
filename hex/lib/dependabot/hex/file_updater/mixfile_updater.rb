# frozen_string_literal: true

require "dependabot/file_updaters/elixir/hex"
require "dependabot/file_updaters/elixir/hex/mixfile_requirement_updater"
require "dependabot/file_updaters/elixir/hex/mixfile_git_pin_updater"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex
        class MixfileUpdater
          def initialize(mixfile:, dependencies:)
            @mixfile = mixfile
            @dependencies = dependencies
          end

          def updated_mixfile_content
            dependencies.
              select { |dep| requirement_changed?(mixfile, dep) }.
              reduce(mixfile.content.dup) do |content, dep|
                updated_content = content

                updated_content = update_requirement(
                  content: updated_content,
                  filename: mixfile.name,
                  dependency: dep
                )

                updated_content = update_git_pin(
                  content: updated_content,
                  filename: mixfile.name,
                  dependency: dep
                )

                if content == updated_content
                  raise "Expected content to change!"
                end

                updated_content
              end
          end

          private

          attr_reader :mixfile, :dependencies

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end

          def update_requirement(content:, filename:, dependency:)
            updated_req =
              dependency.requirements.find { |r| r[:file] == filename }.
              fetch(:requirement)

            old_req =
              dependency.previous_requirements.
              find { |r| r[:file] == filename }.
              fetch(:requirement)

            return content unless old_req

            MixfileRequirementUpdater.new(
              dependency_name: dependency.name,
              mixfile_content: content,
              previous_requirement: old_req,
              updated_requirement: updated_req
            ).updated_content
          end

          def update_git_pin(content:, filename:, dependency:)
            updated_pin =
              dependency.requirements.find { |r| r[:file] == filename }&.
              dig(:source, :ref)

            old_pin =
              dependency.previous_requirements.
              find { |r| r[:file] == filename }&.
              dig(:source, :ref)

            return content unless old_pin
            return content if old_pin == updated_pin

            MixfileGitPinUpdater.new(
              dependency_name: dependency.name,
              mixfile_content: content,
              previous_pin: old_pin,
              updated_pin: updated_pin
            ).updated_content
          end
        end
      end
    end
  end
end
