# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Composer
    module DocumentValueParser
      extend T::Sig

      ObjectHash = T.type_alias { T::Hash[String, Object] }

      sig { params(value: Object, context: String).returns(ObjectHash) }
      def self.object_hash(value, context)
        raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

        value.to_h do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          raise TypeError, "#{context} keys must be strings" unless key.is_a?(String)

          [key, T.cast(raw_value, Object)]
        end
      end

      sig { params(value: Object, context: String).returns(String) }
      def self.string(value, context)
        return value if value.is_a?(String)

        raise TypeError, "#{context} must be a string"
      end

      sig { params(value: Object, context: String).returns(T.nilable(String)) }
      def self.optional_string(value, context)
        return if value.nil?

        string(value, context)
      end
    end
    private_constant :DocumentValueParser
  end
end
