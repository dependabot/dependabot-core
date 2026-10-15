# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "uri"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/composer/document_value_parser"

module Dependabot
  module Composer
    module Package
      class RegistryPackage < T::ImmutableStruct
        extend T::Sig

        class Release < T::ImmutableStruct
          const :version_string, T.nilable(String)
          const :released_at, T.nilable(Time)
          const :url, T.nilable(String)
        end

        const :releases, T::Array[Release]

        sig { params(content: String, package_name: String, source: String).returns(RegistryPackage) }
        def self.from_json(content, package_name:, source:)
          name = package_name.downcase
          context = "Registry '#{source_label(source)}' package '#{name}'"
          value = T.cast(JSON.parse(content), Object)
          return new(releases: []) if value.nil? || value == []

          fields = DocumentValueParser.object_hash(value, context)
          entries = version_entries(fields["packages"], name, context)
          return new(releases: []) if entries.empty?

          new(releases: parse_releases(entries, minified: minified?(fields["minified"], context), context: context))
        rescue JSON::ParserError
          raise DependencyFileNotResolvable.new("#{context} must contain valid JSON"), cause: nil
        rescue TypeError => e
          raise DependencyFileNotResolvable.new(e.message), cause: nil
        end

        sig { params(source: String).returns(String) }
        def self.source_label(source)
          uri = URI.parse(source)
          uri.userinfo = nil
          uri.query = nil
          uri.fragment = nil
          String(uri)
        end
        private_class_method :source_label

        sig { params(value: Object, name: String, context: String).returns(T::Array[Object]) }
        def self.version_entries(value, name, context)
          return [] if value.nil? || value == []

          packages = DocumentValueParser.object_hash(value, "#{context} packages")
          versions = packages[name]
          case versions
          when nil then []
          when Hash then DocumentValueParser.object_hash(versions, "#{context} versions").values
          when Array then versions.map { |entry| T.cast(entry, Object) }
          else raise TypeError, "#{context} versions must be a map or an array"
          end
        end
        private_class_method :version_entries

        sig { params(value: Object, context: String).returns(T::Boolean) }
        def self.minified?(value, context)
          return false if value.nil?
          return true if value == "composer/2.0"

          raise TypeError, "#{context} minified must be composer/2.0 or nil"
        end
        private_class_method :minified?

        sig { params(entries: T::Array[Object], minified: T::Boolean, context: String).returns(T::Array[Release]) }
        def self.parse_releases(entries, minified:, context:)
          previous = T.let(nil, T.nilable(DocumentValueParser::ObjectHash))
          entries.each_with_index.map do |entry, index|
            location = "#{context} releases[#{index}]"
            fields = DocumentValueParser.object_hash(entry, location)
            if minified
              fields = expand_fields(previous, fields)
              previous = fields
            end
            parse_release(fields, location)
          end
        end
        private_class_method :parse_releases

        sig do
          params(previous: T.nilable(DocumentValueParser::ObjectHash), delta: DocumentValueParser::ObjectHash)
            .returns(DocumentValueParser::ObjectHash)
        end
        def self.expand_fields(previous, delta)
          return delta if previous.nil? || previous.empty?

          # composer/2.0 deltas replace top-level fields, not nested members.
          expanded = previous.dup
          delta.each do |key, value|
            if value == "__unset"
              expanded.delete(key)
            else
              expanded[key] = value
            end
          end
          expanded
        end
        private_class_method :expand_fields

        sig { params(fields: DocumentValueParser::ObjectHash, context: String).returns(Release) }
        def self.parse_release(fields, context)
          raise TypeError, "#{context}.version is required" unless fields.key?("version")

          Release.new(
            version_string: DocumentValueParser.optional_string(fields["version"], "#{context}.version"),
            released_at: parse_time(fields["time"], "#{context}.time"),
            url: distribution_url(fields["dist"], "#{context}.dist")
          )
        end
        private_class_method :parse_release

        sig { params(value: Object, context: String).returns(T.nilable(Time)) }
        def self.parse_time(value, context)
          string = DocumentValueParser.optional_string(value, context)
          return if string.nil?

          Time.parse(string)
        rescue ArgumentError
          raise TypeError.new("#{context} must be a valid timestamp"), cause: nil
        end
        private_class_method :parse_time

        sig { params(value: Object, context: String).returns(T.nilable(String)) }
        def self.distribution_url(value, context)
          return if value.nil?

          fields = DocumentValueParser.object_hash(value, context)
          DocumentValueParser.optional_string(fields["url"], "#{context}.url")
        end
        private_class_method :distribution_url
      end
    end
  end
end
