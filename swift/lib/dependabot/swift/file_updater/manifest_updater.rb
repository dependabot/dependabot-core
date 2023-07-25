# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/swift/file_updater/requirement_replacer"

module Dependabot
  module Swift
    class FileUpdater < FileUpdaters::Base
      class ManifestUpdater
        def initialize(content, old_requirements:, new_requirements:)
          @content = content
          @old_requirements = old_requirements
          @new_requirements = new_requirements
        end

        def updated_manifest_content
          updated_content = content

          old_requirements.zip(new_requirements).each do |old, new|
            updated_content = RequirementReplacer.new(
              content: updated_content,
              declaration: old[:metadata][:declaration_string],
              old_requirement: old[:metadata][:requirement_string],
              new_requirement: new[:metadata][:requirement_string]
            ).updated_content
          end

          updated_content
        end

        private

        attr_reader :content, :old_requirements, :new_requirements
      end
    end
  end
end
