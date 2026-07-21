# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/swift/file_updater/requirement_replacer"
require "sorbet-runtime"

module Dependabot
  module Swift
    class FileUpdater < FileUpdaters::Base
      class ManifestUpdater
        extend T::Sig

        sig do
          params(
            content: String,
            old_requirements: T::Array[Dependabot::DependencyRequirement],
            new_requirements: T::Array[Dependabot::DependencyRequirement]
          )
            .void
        end
        def initialize(content, old_requirements:, new_requirements:)
          @content = content
          @old_requirements = old_requirements
          @new_requirements = new_requirements
        end

        sig { returns(String) }
        def updated_manifest_content
          updated_content = content

          old_requirements.zip(new_requirements).each do |old, new|
            updated_content = RequirementReplacer.new(
              content: updated_content,
              declaration: required_metadata_string(old, :declaration_string),
              old_requirement: required_metadata_string(old, :requirement_string),
              new_requirement: required_metadata_string(T.must(new), :requirement_string)
            ).updated_content
          end

          updated_content
        end

        private

        sig { returns(String) }
        attr_reader :content

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :old_requirements

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :new_requirements

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            key: Symbol
          ).returns(String)
        end
        def required_metadata_string(requirement, key)
          value = requirement.metadata_string(key)
          raise TypeError, "Expected #{key} to be a String" unless value.is_a?(String)

          value
        end
      end
    end
  end
end
