# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

module Dependabot
  module Pub
    module JsonValueParser
      extend T::Sig

      class InvalidValue < TypeError; end

      ObjectHash = T.type_alias { T::Hash[String, Object] }

      sig { params(content: String, context: String).returns(Object) }
      def self.parse(content, context)
        T.cast(JSON.parse(content), Object)
      rescue JSON::ParserError
        raise InvalidValue.new("#{context} must be valid JSON"), cause: nil
      end

      sig { params(value: Object, context: String).returns(ObjectHash) }
      def self.object(value, context)
        raise InvalidValue, "#{context} must be an object" unless value.is_a?(Hash)

        value.to_h do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          raise InvalidValue, "#{context} keys must be strings" unless key.is_a?(String)

          [key, T.cast(raw_value, Object)]
        end
      end

      sig { params(value: Object, context: String).returns(T.nilable(ObjectHash)) }
      def self.optional_object(value, context)
        return if value.nil?

        object(value, context)
      end

      sig { params(value: Object, context: String).returns(T::Array[Object]) }
      def self.array(value, context)
        raise InvalidValue, "#{context} must be an array" unless value.is_a?(Array)

        value.map { |entry| T.cast(entry, Object) }
      end

      sig { params(value: Object, context: String).returns(String) }
      def self.string(value, context)
        return value if value.is_a?(String)

        raise InvalidValue, "#{context} must be a string"
      end

      sig { params(value: Object, context: String).returns(T.nilable(String)) }
      def self.optional_string(value, context)
        return if value.nil?
        return value if value.is_a?(String)

        raise InvalidValue, "#{context} must be a string or nil"
      end
    end
  end
end
