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

        # The parsed requirement can include a trailing suffix (a comma before a following
        # argument on the next line, and/or an inline comment). Carry it over when the
        # replacement doesn't already have it, so multi-line declarations stay valid.
        sig { returns(String) }
        def replacement
          suffix = old_requirement[%r{,\s*(?://.*)?\z}] || old_requirement[%r{\s*//.*\z}]
          return new_requirement if suffix.nil? || new_requirement.end_with?(suffix)

          new_requirement + suffix
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
