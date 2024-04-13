# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      class RequirementReplacer
        def initialize(content:, declaration:, old_requirement:, new_requirement:)
          @content         = content
          @declaration     = declaration
          @old_requirement = old_requirement
          @new_requirement = new_requirement
        end

        def updated_content
          content.gsub(declaration) do |match|
            match.to_s.sub(old_requirement, new_requirement)
          end
        end

        private

        attr_reader :content
        attr_reader :declaration
        attr_reader :old_requirement
        attr_reader :new_requirement
      end
    end
  end
end
