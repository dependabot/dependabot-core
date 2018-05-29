# frozen_string_literal: true

require "dependabot/file_updaters/elixir/hex"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex
        class MixfileRequirementUpdater
          def initialize(dependency_name:, mixfile_content:,
                         previous_requirement:, updated_requirement:,
                         insert_if_bare: false)
            @dependency_name      = dependency_name
            @mixfile_content      = mixfile_content
            @previous_requirement = previous_requirement
            @updated_requirement  = updated_requirement
            @insert_if_bare       = insert_if_bare
          end

          def updated_content
            updated_content = update_requirement(mixfile_content)

            if content_should_change? && mixfile_content == updated_content
              raise "Expected content to change!"
            end

            updated_content
          end

          private

          attr_reader :dependency_name, :mixfile_content,
                      :previous_requirement, :updated_requirement

          def insert_if_bare?
            !@insert_if_bare.nil?
          end

          def update_requirement(content)
            return content if previous_requirement.nil? && !insert_if_bare?

            requirement_line_regex =
              if previous_requirement
                /
                  :#{Regexp.escape(dependency_name)},.*
                  #{Regexp.escape(previous_requirement)}
                /x
              else
                /:#{Regexp.escape(dependency_name)}(,|\s|\})/
              end

            content.gsub(requirement_line_regex) do |requirement_line|
              if previous_requirement
                requirement_line.gsub(previous_requirement, updated_requirement)
              else
                requirement_line.gsub(
                  ":#{dependency_name}",
                  ":#{dependency_name}, \"#{updated_requirement}\""
                )
              end
            end
          end

          def content_should_change?
            return false if previous_requirement == updated_requirement
            previous_requirement || insert_if_bare?
          end
        end
      end
    end
  end
end
