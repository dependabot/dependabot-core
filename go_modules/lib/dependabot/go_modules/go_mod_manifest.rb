# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/shared_helpers"

module Dependabot
  module GoModules
    class GoModManifest < T::ImmutableStruct
      extend T::Sig

      class InvalidOutput < SharedHelpers::HelperSubprocessFailed; end

      class RequirementEntry < T::ImmutableStruct
        const :path, String
        const :version, T.nilable(String)
        const :indirect, T::Boolean
      end

      class ModuleReference < T::ImmutableStruct
        const :path, String
        const :version, T.nilable(String)
      end

      class Replacement < T::ImmutableStruct
        const :old, ModuleReference
        const :new, ModuleReference
      end

      class Exclusion < T::ImmutableStruct
        const :path, String
        const :version, String
      end

      ObjectHash = T.type_alias { T::Hash[String, Object] }

      const :requirements, T::Array[RequirementEntry]
      const :replacements, T::Array[Replacement]
      const :exclusions, T::Array[Exclusion]

      sig { params(content: String, file_path: String).returns(GoModManifest) }
      def self.from_json(content, file_path:)
        context = "go mod edit -json for #{file_path}"
        fields = object(T.cast(JSON.parse(content), Object), "#{context}: result")
        new(
          requirements: parse_requirements(fields["Require"], "#{context}: Require"),
          replacements: parse_replacements(fields["Replace"], "#{context}: Replace"),
          exclusions: parse_exclusions(fields["Exclude"], "#{context}: Exclude")
        )
      rescue JSON::ParserError
        invalid_output("#{context}: result must be valid JSON")
      end

      sig { params(value: Object, context: String).returns(T::Array[RequirementEntry]) }
      def self.parse_requirements(value, context)
        array(value, context).each_with_index.map do |entry, index|
          location = "#{context}[#{index}]"
          fields = object(entry, location)
          RequirementEntry.new(
            path: string(fields["Path"], "#{location}.Path"),
            version: optional_string(fields["Version"], "#{location}.Version"),
            indirect: indirect(fields["Indirect"], "#{location}.Indirect")
          )
        end
      end
      private_class_method :parse_requirements

      sig { params(value: Object, context: String).returns(T::Array[Replacement]) }
      def self.parse_replacements(value, context)
        array(value, context).each_with_index.map do |entry, index|
          location = "#{context}[#{index}]"
          fields = object(entry, location)
          Replacement.new(
            old: module_reference(fields["Old"], "#{location}.Old"),
            new: module_reference(fields["New"], "#{location}.New")
          )
        end
      end
      private_class_method :parse_replacements

      sig { params(value: Object, context: String).returns(T::Array[Exclusion]) }
      def self.parse_exclusions(value, context)
        array(value, context).each_with_index.map do |entry, index|
          location = "#{context}[#{index}]"
          fields = object(entry, location)
          Exclusion.new(
            path: string(fields["Path"], "#{location}.Path"),
            version: string(fields["Version"], "#{location}.Version")
          )
        end
      end
      private_class_method :parse_exclusions

      sig { params(value: Object, context: String).returns(ModuleReference) }
      def self.module_reference(value, context)
        fields = object(value, context)
        ModuleReference.new(
          path: string(fields["Path"], "#{context}.Path"),
          version: optional_string(fields["Version"], "#{context}.Version")
        )
      end
      private_class_method :module_reference

      sig { params(value: Object, context: String).returns(ObjectHash) }
      def self.object(value, context)
        invalid_output("#{context} must be an object") unless value.is_a?(Hash)

        value.to_h do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          invalid_output("#{context} keys must be strings") unless key.is_a?(String)

          [key, T.cast(raw_value, Object)]
        end
      end
      private_class_method :object

      sig { params(value: Object, context: String).returns(T::Array[Object]) }
      def self.array(value, context)
        return [] if value.nil?

        invalid_output("#{context} must be an array") unless value.is_a?(Array)
        value.map { |entry| T.cast(entry, Object) }
      end
      private_class_method :array

      sig { params(value: Object, context: String).returns(String) }
      def self.string(value, context)
        return value if value.is_a?(String)

        invalid_output("#{context} must be a string")
      end
      private_class_method :string

      sig { params(value: Object, context: String).returns(T.nilable(String)) }
      def self.optional_string(value, context)
        return if value.nil?

        string(value, context)
      end
      private_class_method :optional_string

      sig { params(value: Object, context: String).returns(T::Boolean) }
      def self.indirect(value, context)
        case value
        when nil, false then false
        when true then true
        else invalid_output("#{context} must be a boolean or nil")
        end
      end
      private_class_method :indirect

      sig { params(message: String).returns(T.noreturn) }
      def self.invalid_output(message)
        raise InvalidOutput.new(
          message: message,
          error_class: "TypeError",
          error_context: { command: "go mod edit -json" }
        ),
              cause: nil
      end
      private_class_method :invalid_output
    end
  end
end
