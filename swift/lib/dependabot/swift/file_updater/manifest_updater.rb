# typed: strict
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
            old_requirements: T::Array[T::Hash[Symbol, T.untyped]],
            new_requirements: T::Array[T::Hash[Symbol, T.untyped]]
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
              declaration: old[:metadata][:declaration_string],
              old_requirement: old[:metadata][:requirement_string],
              new_requirement: T.must(new)[:metadata][:requirement_string]
            ).updated_content
          end

          updated_content
        end

        private

        sig { returns(String) }
        attr_reader :content

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :old_requirements

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :new_requirements
      end
    end
  end
end
