# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/hex/file_updater"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    class FileUpdater
      class MixfileRequirementUpdater
        extend T::Sig

        sig do
          params(
            dependency_name: String,
            mixfile_content: String,
            previous_requirement: T.nilable(String),
            updated_requirement: T.nilable(String),
            insert_if_bare: T::Boolean
          ).void
        end
        def initialize(dependency_name:, mixfile_content:,
                       previous_requirement:, updated_requirement:,
                       insert_if_bare: false)
          @dependency_name      = T.let(dependency_name, String)
          @mixfile_content      = T.let(mixfile_content, String)
          @previous_requirement = T.let(previous_requirement, T.nilable(String))
          @updated_requirement  = T.let(updated_requirement, T.nilable(String))
          @insert_if_bare       = T.let(insert_if_bare, T::Boolean)
        end

        sig { returns(String) }
        def updated_content
          updated_content = update_requirement(mixfile_content)

          raise "Expected content to change!" if content_should_change? && mixfile_content == updated_content

          updated_content
        end

        private

        sig { returns(String) }
        attr_reader :dependency_name

        sig { returns(String) }
        attr_reader :mixfile_content

        sig { returns(T.nilable(String)) }
        attr_reader :previous_requirement

        sig { returns(T.nilable(String)) }
        attr_reader :updated_requirement

        sig { returns(T::Boolean) }
        def insert_if_bare?
          @insert_if_bare
        end

        sig { params(content: String).returns(String) }
        def update_requirement(content)
          return content if previous_requirement.nil? && !insert_if_bare?

          requirement_line_regex =
            if previous_requirement
              /
                :#{Regexp.escape(dependency_name)}\s*,.*
                #{Regexp.escape(T.must(previous_requirement))}
              /x
            else
              /:#{Regexp.escape(dependency_name)}(,|\s|\})/
            end

          content.gsub(requirement_line_regex) do |requirement_line|
            if previous_requirement && updated_requirement
              requirement_line.gsub(T.must(previous_requirement), T.must(updated_requirement))
            elsif updated_requirement
              requirement_line.gsub(
                ":#{dependency_name}",
                ":#{dependency_name}, \"#{T.must(updated_requirement)}\""
              )
            else
              # If we don't have an updated requirement, return the line unchanged
              requirement_line
            end
          end
        end

        sig { returns(T::Boolean) }
        def content_should_change?
          return false if previous_requirement == updated_requirement
          return false if updated_requirement.nil? && !insert_if_bare?

          !previous_requirement.nil? || insert_if_bare?
        end
      end
    end
  end
end
