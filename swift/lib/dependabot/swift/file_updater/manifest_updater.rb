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
            old_requirements: T::Array[T::Hash[Symbol, Object]],
            new_requirements: T::Array[T::Hash[Symbol, Object]]
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
            old_metadata = metadata(old)
            new_metadata = metadata(T.must(new))
            updated_content = RequirementReplacer.new(
              content: updated_content,
              declaration: string_value(old_metadata, :declaration_string),
              old_requirement: string_value(old_metadata, :requirement_string),
              new_requirement: string_value(new_metadata, :requirement_string)
            ).updated_content
          end

          updated_content
        end

        private

        sig { returns(String) }
        attr_reader :content

        sig { returns(T::Array[T::Hash[Symbol, Object]]) }
        attr_reader :old_requirements

        sig { returns(T::Array[T::Hash[Symbol, Object]]) }
        attr_reader :new_requirements

        sig { params(requirement: T::Hash[Symbol, Object]).returns(T::Hash[Symbol, Object]) }
        def metadata(requirement)
          value = requirement[:metadata]
          raise TypeError, "Expected metadata to be a Hash" unless value.is_a?(Hash)

          value
        end

        sig { params(hash: T::Hash[Symbol, Object], key: Symbol).returns(String) }
        def string_value(hash, key)
          value = hash.fetch(key)
          raise TypeError, "Expected #{key} to be a String" unless value.is_a?(String)

          value
        end
      end
    end
  end
end
