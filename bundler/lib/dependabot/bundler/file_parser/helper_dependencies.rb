# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/bundler/file_parser"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      module HelperDependencies
        extend T::Sig

        Source = T.type_alias { T::Hash[Symbol, T.nilable(String)] }
        ObjectHash = T.type_alias { T::Hash[String, Object] }

        class GemfileDependency < T::ImmutableStruct
          const :name, String
          const :requirement, String
          const :groups, T::Array[String]
          const :source, T.nilable(Source)
        end

        class GemspecDependency < T::ImmutableStruct
          const :name, String
          const :requirement, String
          const :type, String
          const :source, T.nilable(Source)
        end

        # Both helper versions serialize these fields in Functions::FileParser#serialize_bundler_dependency.
        sig { params(result: Object, file: Dependabot::DependencyFile).returns(T::Array[GemfileDependency]) }
        def self.from_gemfile_result(result, file:)
          context = "parsed_gemfile result for #{file.path}"
          array(result, context).each_with_index.map do |value, index|
            entry_context = "#{context}[#{index}]"
            entry = object(value, entry_context)

            GemfileDependency.new(
              name: string(entry["name"], "#{entry_context}.name"),
              requirement: string(entry["requirement"], "#{entry_context}.requirement"),
              groups: strings(entry["groups"], "#{entry_context}.groups"),
              source: source(entry, entry_context)
            )
          end
        end

        sig { params(result: Object, file: Dependabot::DependencyFile).returns(T::Array[GemspecDependency]) }
        def self.from_gemspec_result(result, file:)
          context = "parsed_gemspec result for #{file.path}"
          array(result, context).each_with_index.map do |value, index|
            entry_context = "#{context}[#{index}]"
            entry = object(value, entry_context)

            GemspecDependency.new(
              name: string(entry["name"], "#{entry_context}.name"),
              requirement: string(entry["requirement"], "#{entry_context}.requirement"),
              type: string(entry["type"], "#{entry_context}.type"),
              source: source(entry, entry_context)
            )
          end
        end

        sig { params(entry: ObjectHash, context: String).returns(T.nilable(Source)) }
        def self.source(entry, context)
          raise DependencyFileNotEvaluatable, "#{context}.source must be present" unless entry.key?("source")

          value = entry["source"]
          return if value.nil?

          fields = object(value, "#{context}.source")
          string(fields["type"], "#{context}.source.type")
          fields.to_h do |key, field|
            [key.to_sym, field.nil? ? nil : string(field, "#{context}.source.#{key}")]
          end
        end
        private_class_method :source

        sig { params(value: Object, context: String).returns(ObjectHash) }
        def self.object(value, context)
          raise DependencyFileNotEvaluatable, "#{context} must be an object" unless value.is_a?(Hash)

          value.to_h do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            raise DependencyFileNotEvaluatable, "#{context} keys must be strings" unless key.is_a?(String)

            [key, T.cast(raw_value, Object)]
          end
        end
        private_class_method :object

        sig { params(value: Object, context: String).returns(T::Array[Object]) }
        def self.array(value, context)
          raise DependencyFileNotEvaluatable, "#{context} must be an array" unless value.is_a?(Array)

          value.map { |entry| T.cast(entry, Object) }
        end
        private_class_method :array

        sig { params(value: Object, context: String).returns(String) }
        def self.string(value, context)
          return value if value.is_a?(String)

          raise DependencyFileNotEvaluatable, "#{context} must be a string"
        end
        private_class_method :string

        sig { params(value: Object, context: String).returns(T::Array[String]) }
        def self.strings(value, context)
          array(value, context).each_with_index.map { |entry, index| string(entry, "#{context}[#{index}]") }
        end
        private_class_method :strings
      end
    end
  end
end
