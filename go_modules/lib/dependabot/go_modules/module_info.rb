# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"
require "dependabot/shared_helpers"

module Dependabot
  module GoModules
    class ModuleInfo < T::ImmutableStruct
      extend T::Sig

      class InvalidOutput < SharedHelpers::HelperSubprocessFailed; end

      ObjectHash = T.type_alias { T::Hash[String, Object] }

      const :versions, T.nilable(T::Array[String])
      const :released_at, T.nilable(Time)

      sig { params(content: String, command: String).returns(ModuleInfo) }
      def self.from_json(content, command:)
        fields = object(T.cast(JSON.parse(content), Object), command)
        new(
          versions: parse_versions(fields["Versions"], command),
          released_at: parse_time(fields["Time"], command)
        )
      rescue JSON::ParserError
        invalid_output(command, "result must be valid JSON")
      end

      sig { params(value: Object, command: String).returns(ObjectHash) }
      def self.object(value, command)
        invalid_output(command, "result must be an object") unless value.is_a?(Hash)

        value.to_h do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          invalid_output(command, "result keys must be strings") unless key.is_a?(String)

          [key, T.cast(raw_value, Object)]
        end
      end
      private_class_method :object

      sig { params(value: Object, command: String).returns(T.nilable(T::Array[String])) }
      def self.parse_versions(value, command)
        return if value.nil?

        invalid_output(command, "Versions must be an array or nil") unless value.is_a?(Array)
        value.each_with_index.map do |raw_entry, index|
          entry = T.cast(raw_entry, Object)
          invalid_output(command, "Versions[#{index}] must be a string") unless entry.is_a?(String)

          entry
        end
      end
      private_class_method :parse_versions

      sig { params(value: Object, command: String).returns(T.nilable(Time)) }
      def self.parse_time(value, command)
        return if value.nil?

        invalid_output(command, "Time must be a string or nil") unless value.is_a?(String)
        Time.parse(value)
      rescue ArgumentError
        invalid_output(command, "Time must be a valid timestamp")
      end
      private_class_method :parse_time

      sig { params(command: String, message: String).returns(T.noreturn) }
      def self.invalid_output(command, message)
        raise InvalidOutput.new(
          message: "#{command}: #{message}",
          error_class: "TypeError",
          error_context: { command: command }
        ),
              cause: nil
      end
      private_class_method :invalid_output
    end
  end
end
