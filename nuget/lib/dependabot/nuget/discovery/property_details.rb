# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nuget
    class PropertyDetails
      extend T::Sig

      sig { params(json: T::Hash[String, T.untyped]).returns(PropertyDetails) }
      def self.from_json(json)
        name = T.let(json.fetch("Name"), String)
        value = T.let(json.fetch("Value"), String)
        source_file_path = T.let(json.fetch("SourceFilePath"), String)

        PropertyDetails.new(name: name,
                            value: value,
                            source_file_path: source_file_path)
      end

      sig do
        params(name: String,
               value: String,
               source_file_path: String).void
      end
      def initialize(name:, value:, source_file_path:)
        @name = name
        @value = value
        @source_file_path = source_file_path
      end

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :value

      sig { returns(String) }
      attr_reader :source_file_path
    end
  end
end
