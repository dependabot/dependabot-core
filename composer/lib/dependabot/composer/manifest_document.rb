# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/composer/document_value_parser"

module Dependabot
  module Composer
    class ManifestDocument
      extend T::Sig

      class DependencyEntry
        extend T::Sig

        sig { params(name: String, value: Object, context: String).void }
        def initialize(name:, value:, context:)
          @name = name
          @value = value
          @context = context
        end

        sig { returns(String) }
        attr_reader :name

        sig { returns(T.nilable(String)) }
        def string_requirement
          value = @value
          value if value.is_a?(String)
        end

        sig { returns(String) }
        def requirement
          DocumentValueParser.string(@value, @context)
        end
      end

      class Repository
        extend T::Sig

        sig { params(type: String, url: Object, context: String).void }
        def initialize(type:, url:, context:)
          @type = type
          @url = url
          @context = context
        end

        sig { returns(String) }
        attr_reader :type

        sig { returns(String) }
        def url
          DocumentValueParser.string(@url, "#{@context} url")
        end
      end

      sig { params(file: Dependabot::DependencyFile).returns(ManifestDocument) }
      def self.from_file(file)
        new(data: T.cast(JSON.parse(T.must(file.content)), Object), context: file.path)
      end

      sig { params(data: Object, context: String).void }
      def initialize(data:, context:)
        @data = T.let(DocumentValueParser.object_hash(data, context), DocumentValueParser::ObjectHash)
        @context = context
      end

      sig { returns(T.nilable(String)) }
      def name
        value = @data["name"]
        return unless value

        DocumentValueParser.string(value, "#{@context} name")
      end

      sig { params(group: String).returns(T::Array[DependencyEntry]) }
      def requirements(group)
        value = @data[group]
        return [] unless value.is_a?(Hash)

        DocumentValueParser.object_hash(value, "#{@context} #{group}").map do |name, requirement|
          DependencyEntry.new(name: name, value: requirement, context: "#{@context} #{group} requirement")
        end
      end

      sig { returns(T::Array[String]) }
      def required_dependency_names
        return [] unless @data.key?("require")

        DocumentValueParser.object_hash(@data.fetch("require"), "#{@context} require").keys
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def platform(name)
        config = section(@data, "config", "config")
        platform = config && section(config, "platform", "config.platform")
        DocumentValueParser.optional_string(platform&.[](name), "#{@context} config.platform.#{name}")
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def dependency_constraint(name)
        requirements = section(@data, "require", "require")
        DocumentValueParser.optional_string(requirements&.[](name), "#{@context} require.#{name}")
      end

      sig { returns(T::Array[Repository]) }
      def repositories
        value = @data["repositories"]
        entries =
          case value
          when Hash then value.values
          when Array then value
          else return []
          end

        entries.each_with_index.filter_map do |raw_entry, index|
          entry = T.cast(raw_entry, Object)
          next unless entry.is_a?(Hash)

          context = "#{@context} repositories[#{index}]"
          details = DocumentValueParser.object_hash(entry, context)
          type = details["type"]
          next unless type.is_a?(String) && (type == "path" || type == "artifact")

          Repository.new(type: type, url: details["url"], context: context)
        end
      end

      private

      sig do
        params(data: DocumentValueParser::ObjectHash, key: String, field: String)
          .returns(T.nilable(DocumentValueParser::ObjectHash))
      end
      def section(data, key, field)
        value = data[key]
        return if value.nil?

        DocumentValueParser.object_hash(value, "#{@context} #{field}")
      end
    end
  end
end
