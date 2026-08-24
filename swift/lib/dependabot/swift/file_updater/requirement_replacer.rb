# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "sorbet-runtime"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      class RequirementReplacer
        extend T::Sig

        sig do
          params(
            content: String,
            declaration: String,
            old_requirement: String,
            new_requirement: String
          ).void
        end
        def initialize(content:, declaration:, old_requirement:, new_requirement:)
          @content         = content
          @declaration     = declaration
          @old_requirement = old_requirement
          @new_requirement = new_requirement
        end

        sig { returns(String) }
        def updated_content
          content.gsub(declaration) do |match|
            match.to_s.sub(old_requirement, replacement)
          end
        end

        private

        # The parsed requirement can include a trailing separator (e.g. a comma before a
        # following argument on the next line). Carry it over when the replacement doesn't
        # already have one, so multi-line declarations stay valid.
        sig { returns(String) }
        def replacement
          trailing_separator = old_requirement[/,\s*\z/]
          return new_requirement if trailing_separator.nil?
          return new_requirement if new_requirement.match?(/,\s*\z/)

          new_requirement + trailing_separator
        end

        sig { returns(String) }
        attr_reader :content

        sig { returns(String) }
        attr_reader :declaration

        sig { returns(String) }
        attr_reader :old_requirement

        sig { returns(String) }
        attr_reader :new_requirement
      end
    end
  end
end
