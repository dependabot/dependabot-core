# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nuget
    class EvaluationDetails
      extend T::Sig

      sig { params(json: T.nilable(T::Hash[String, T.untyped])).returns(T.nilable(EvaluationDetails)) }
      def self.from_json(json)
        return nil if json.nil?

        result_type = T.let(json.fetch("ResultType"), String)
        original_value = T.let(json.fetch("OriginalValue"), String)
        evaluated_value = T.let(json.fetch("EvaluatedValue"), String)
        first_property_name = T.let(json.fetch("FirstPropertyName", nil), T.nilable(String))
        last_property_name = T.let(json.fetch("LastPropertyName", nil), T.nilable(String))
        error_message = T.let(json.fetch("ErrorMessage", nil), T.nilable(String))

        EvaluationDetails.new(result_type: result_type,
                              original_value: original_value,
                              evaluated_value: evaluated_value,
                              first_property_name: first_property_name,
                              last_property_name: last_property_name,
                              error_message: error_message)
      end

      sig do
        params(result_type: String,
               original_value: String,
               evaluated_value: String,
               first_property_name: T.nilable(String),
               last_property_name: T.nilable(String),
               error_message: T.nilable(String)).void
      end
      def initialize(result_type:,
                     original_value:,
                     evaluated_value:,
                     first_property_name:,
                     last_property_name:,
                     error_message:)
        @result_type = result_type
        @original_value = original_value
        @evaluated_value = evaluated_value
        @first_property_name = first_property_name
        @last_property_name = last_property_name
        @error_message = error_message
      end

      sig { returns(String) }
      attr_reader :result_type

      sig { returns(String) }
      attr_reader :original_value

      sig { returns(String) }
      attr_reader :evaluated_value

      sig { returns(T.nilable(String)) }
      attr_reader :first_property_name

      sig { returns(T.nilable(String)) }
      attr_reader :last_property_name

      sig { returns(T.nilable(String)) }
      attr_reader :error_message
    end
  end
end
