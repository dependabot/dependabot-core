# typed: strong
# frozen_string_literal: true

require "json"

require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Clients
    module JsonResponseParser
      extend T::Sig

      JsonObject = T.type_alias { T::Hash[String, Object] }
      JsonObjects = T.type_alias { T::Array[JsonObject] }

      private

      sig { params(body: String, context: String).returns(JsonObject) }
      def parse_json_object(body, context)
        value = T.cast(JSON.parse(body), Object)
        return T.let(value, JsonObject) if value.is_a?(Hash)

        raise_bad_response(context, "expected an object")
      rescue JSON::ParserError => e
        raise_bad_response(context, e.message)
      end

      sig { params(object: JsonObject, key: String, context: String).returns(JsonObject) }
      def object_field(object, key, context)
        value = object.fetch(key)
        return T.let(value, JsonObject) if value.is_a?(Hash)

        raise_bad_response(context, "#{key} must be an object")
      rescue KeyError => e
        raise_bad_response(context, e.message)
      end

      sig { params(object: JsonObject, key: String, context: String).returns(String) }
      def string_field(object, key, context)
        string_value(object.fetch(key), context)
      rescue KeyError => e
        raise_bad_response(context, e.message)
      end

      sig { params(value: Object, context: String).returns(String) }
      def string_value(value, context)
        return value if value.is_a?(String)

        raise_bad_response(context, "expected a string")
      end

      sig { params(object: JsonObject, key: String, context: String).returns(JsonObjects) }
      def object_array_field(object, key, context)
        object_array(object.fetch(key), context)
      rescue KeyError => e
        raise_bad_response(context, e.message)
      end

      sig { params(value: Object, context: String).returns(JsonObjects) }
      def object_array(value, context)
        raise_bad_response(context, "expected an array") unless value.is_a?(Array)

        value.map do |raw_entry|
          entry = T.cast(raw_entry, Object)
          next T.let(entry, JsonObject) if entry.is_a?(Hash)

          raise_bad_response(context, "array entries must be objects")
        end
      end

      sig { params(object: JsonObject, key: String, context: String).returns(JsonObject) }
      def first_object_field(object, key, context)
        value = object_array_field(object, key, context).first
        return value if value

        raise_bad_response(context, "#{key} must contain at least one object")
      end

      sig { params(object: JsonObject, context: String, paths: T::Array[T::Array[String]]).void }
      def validate_string_paths(object, context, paths)
        paths.each do |path|
          current = T.must(path[0...-1]).reduce(object) { |value, key| object_field(value, key, context) }
          string_field(current, T.must(path.last), context)
        end
      end

      sig { params(context: String, message: String).returns(T.noreturn) }
      def raise_bad_response(context, message)
        provider, source = response_identity
        Kernel.raise Dependabot::PrivateSourceBadResponse.new(
          source,
          "Malformed #{provider} response for #{context}: #{message}"
        )
      end

      sig { returns([String, String]) }
      def response_identity
        Kernel.raise NotImplementedError
      end
    end
  end
end
