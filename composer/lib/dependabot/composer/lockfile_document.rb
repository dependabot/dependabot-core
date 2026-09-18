# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/dependency_requirement"
require "dependabot/composer/document_value_parser"

module Dependabot
  module Composer
    class LockfileDocument
      extend T::Sig

      class PackageRecord
        extend T::Sig

        sig { params(data: DocumentValueParser::ObjectHash, context: String).void }
        def initialize(data:, context:)
          @data = data
          @context = context
        end

        sig { returns(T.nilable(String)) }
        def name
          value = @data["name"]
          value if value.is_a?(String)
        end

        sig { returns(T.nilable(String)) }
        def version
          @data["version"]&.to_s
        end

        sig { returns(T.nilable(String)) }
        def required_version
          @data.fetch("version")&.to_s
        end

        sig { returns(T::Boolean) }
        def path_source?
          @data["source"].nil? && path_distribution?
        end

        sig { returns(T::Boolean) }
        def path_distribution?
          section("dist")&.[]("type") == "path"
        end

        sig { params(path: String).returns(T::Boolean) }
        def matches_distribution_path?(path)
          section("dist")&.[]("url") == path
        end

        sig { params(prefix: String).returns(T::Boolean) }
        def dist_url_starts_with?(prefix)
          section("dist")&.[]("url").to_s.start_with?(prefix)
        end

        sig { returns(String) }
        def dist_url
          DocumentValueParser.string(section("dist")&.[]("url"), "#{@context} dist.url")
        end

        sig { returns(String) }
        def to_manifest_json
          @data.to_json
        end

        sig { returns(T.nilable(String)) }
        def source_reference
          DocumentValueParser.optional_string(section("source")&.[]("reference"), "#{@context} source.reference")
        end

        sig { returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash)) }
        def git_source
          source = section("source")
          return unless source && source["type"] == "git"

          # The URL is passed through as source metadata, not interpreted by the file parser.
          { type: "git", url: source["url"] }
        end

        private

        sig { params(key: String).returns(T.nilable(DocumentValueParser::ObjectHash)) }
        def section(key)
          value = @data[key]
          return if value.nil?

          DocumentValueParser.object_hash(value, "#{@context} #{key}")
        end
      end

      sig { params(file: Dependabot::DependencyFile).returns(LockfileDocument) }
      def self.from_file(file)
        new(data: T.cast(JSON.parse(T.must(file.content)), Object), context: file.path)
      end

      sig { params(data: Object, context: String).void }
      def initialize(data:, context:)
        @data = T.let(DocumentValueParser.object_hash(data, context), DocumentValueParser::ObjectHash)
        @context = context
      end

      sig { returns(T.nilable(T.any(String, Integer))) }
      def plugin_api_version
        value = @data["plugin-api-version"]
        return unless value
        return value if value.is_a?(String) || value.is_a?(Integer)

        raise TypeError, "#{@context} plugin-api-version must be a string or integer"
      end

      sig { params(group: String).returns(T::Array[PackageRecord]) }
      def packages(group)
        entries = @data[group]
        return [] unless entries.is_a?(Array)

        entries.each_with_index.filter_map { |entry, index| package_record(T.cast(entry, Object), group, index) }
      end

      sig { params(group: String, name: String).returns(T.nilable(PackageRecord)) }
      def find_package(group, name)
        entries = @data.fetch(group, [])
        return if entries.nil?
        raise TypeError, "#{@context} #{group} must be an array" unless entries.is_a?(Array)

        entries.each_with_index do |entry, index|
          package = package_record(T.cast(entry, Object), group, index)
          return package if package&.name == name
        end
        nil
      end

      sig { params(group: String).returns(T::Array[PackageRecord]) }
      def path_packages(group)
        distribution_entries(group).each_with_index.filter_map do |entry, index|
          package = strict_package_record(entry, group, index)
          package if package.path_distribution?
        end
      end

      sig { params(group: String, path: String).returns(T.nilable(PackageRecord)) }
      def find_path_package(group, path)
        distribution_entries(group).each_with_index do |entry, index|
          package = strict_package_record(entry, group, index)
          return package if package.matches_distribution_path?(path)
        end
        nil
      end

      private

      sig { params(group: String).returns(T::Array[Object]) }
      def distribution_entries(group)
        entries = @data[group]
        return [] unless entries
        return [] if entries.is_a?(Hash) && entries.empty?
        raise TypeError, "#{@context} #{group} must be an array" unless entries.is_a?(Array)

        entries.map { |entry| T.cast(entry, Object) }
      end

      sig { params(value: Object, group: String, index: Integer).returns(T.nilable(PackageRecord)) }
      def package_record(value, group, index)
        return if value.is_a?(String)

        strict_package_record(value, group, index)
      end

      sig { params(value: Object, group: String, index: Integer).returns(PackageRecord) }
      def strict_package_record(value, group, index)
        context = "#{@context} #{group}[#{index}]"
        PackageRecord.new(data: DocumentValueParser.object_hash(value, context), context: context)
      end
    end
  end
end
