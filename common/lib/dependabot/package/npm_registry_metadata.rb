# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"

require "dependabot/source"

module Dependabot
  module Package
    class NpmRegistryMetadata
      extend T::Sig

      JsonObject = T.type_alias { T::Hash[String, Object] }
      VersionKey = T.type_alias { T.any(String, Integer) }

      class SourceLink
        extend T::Sig

        GITHUB_SHORTHAND = %r{^[\w.-]+/[\w.-]+$}

        sig { returns(String) }
        attr_reader :url

        sig { params(url: String, directory: Object).void }
        def initialize(url, directory: nil)
          @url = url
          @directory = directory
        end

        sig { params(value: Object).returns(T.nilable(SourceLink)) }
        def self.parse(value)
          directory = T.let(nil, Object)
          url =
            case value
            when nil then return
            when String then value
            when Hash
              fields = T.let(value, JsonObject)
              directory = fields["directory"]
              fields["url"]
            when Array
              strings = T.let(value, T::Array[Object]).grep(String)
              strings.find { |string| string.match?(GITHUB_SHORTHAND) } || strings.first
            else
              raise TypeError, "Registry source link must be a string, object, or array"
            end

          return if url.nil?
          raise NoMethodError, "Registry source link URL does not support match?" unless url.is_a?(String)

          url = "https://github.com/#{url}" if url.match?(GITHUB_SHORTHAND)
          new(url, directory: directory)
        end

        sig { returns(T.nilable(Dependabot::Source)) }
        def to_source
          source = Source.from_url(url)
          return unless source

          directory = @directory
          raise TypeError, "Registry source directory must be a string" unless directory.nil? || directory.is_a?(String)

          source.directory = directory
          source
        end
      end

      class LifecycleScripts
        extend T::Sig

        sig { params(entries: JsonObject).void }
        def initialize(entries = {})
          @entries = entries
        end

        sig { params(previous: LifecycleScripts).returns(T::Array[String]) }
        def added_since(previous)
          entries.keys - previous.entries.keys
        end

        sig { params(previous: LifecycleScripts).returns(T::Array[String]) }
        def modified_since(previous)
          (entries.keys & previous.entries.keys).reject { |name| entries[name] == previous.entries[name] }
        end

        protected

        sig { returns(JsonObject) }
        attr_reader :entries
      end

      class Listing
        extend T::Sig

        sig { params(fields: T.any(JsonObject, String)).void }
        def initialize(fields = {})
          @fields = fields
        end

        sig { params(block: T.proc.params(link: SourceLink).void).void }
        def each_source_link(&block)
          %w(repository homepage bugs).each do |key|
            link = SourceLink.parse(@fields[key])
            yield link if link
          end
        end

        sig { returns(T.nilable(String)) }
        def homepage
          value = @fields["homepage"]
          return unless value

          raise NoMethodError, "Registry version details do not support fetch" if @fields.is_a?(String)
          return value if value.is_a?(String)

          raise TypeError, "Registry homepage must be a string"
        end

        sig { returns(T::Boolean) }
        def deprecated?
          !!@fields["deprecated"]
        end

        sig { returns(T.nilable(String)) }
        def releaser
          value = releaser_name
          return if value.nil?
          return value if value.is_a?(String)

          raise TypeError, "Registry releaser name must be a string"
        end

        sig { returns(T.nilable(String)) }
        def historical_releaser
          value = releaser_name
          value if value.is_a?(String)
        end

        sig { returns(T::Boolean) }
        def attested?
          nested_field("dist", "attestations").is_a?(Hash)
        end

        sig { params(names: T::Array[String]).returns(LifecycleScripts) }
        def lifecycle_scripts(names)
          scripts = @fields["scripts"]
          return LifecycleScripts.new unless scripts

          case scripts
          when Hash
            fields = T.let(scripts, JsonObject)
            entries = names.each_with_object(T.let({}, JsonObject)) do |name, selected|
              selected[name] = fields.fetch(name) if fields.key?(name)
            end
            LifecycleScripts.new(entries)
          when String, Array
            raise ArgumentError, "Registry scripts must be an object to select lifecycle entries"
          else
            raise NoMethodError, "Registry scripts do not support slice"
          end
        end

        private

        sig { returns(Object) }
        def releaser_name
          nested_field("_npmUser", "name")
        end

        sig { params(field: String, key: String).returns(Object) }
        def nested_field(field, key)
          raise NoMethodError, "Registry version details do not support dig" if @fields.is_a?(String)

          NpmRegistryMetadata.nested_field(@fields[field], key)
        end
      end

      class VersionListing < T::ImmutableStruct
        const :version, VersionKey
        const :listing, Listing
      end

      sig { params(json: String).returns(Listing) }
      def self.latest_from_json(json)
        Listing.new(decode(json))
      end

      sig { params(json: String).returns(NpmRegistryMetadata) }
      def self.from_json(json)
        new(decode(json))
      end

      sig { params(json: String).returns(JsonObject) }
      def self.decode(json)
        value = T.cast(JSON.parse(json), Object)
        return T.let(value, JsonObject) if value.is_a?(Hash)

        {}
      end
      private_class_method :decode

      sig { params(value: Object, key: T.nilable(VersionKey)).returns(Object) }
      def self.nested_field(value, key)
        case value
        when nil then nil
        when Hash then T.let(value, JsonObject)[key] if key.is_a?(String)
        when Array
          raise TypeError, "no implicit conversion of #{key.class} into Integer" unless key.is_a?(Integer)

          T.let(value, T::Array[Object])[key]
        else raise TypeError, "#{value.class} does not have #dig method"
        end
      end

      sig { params(fields: JsonObject).void }
      def initialize(fields = {})
        @fields = fields
      end

      sig { returns(T::Array[VersionListing]) }
      def version_listings
        versions = @fields["versions"]
        return [] if versions.nil?
        unless versions.is_a?(Hash) || versions.is_a?(Array)
          raise NoMethodError, "Registry versions do not support filtering"
        end

        versions.filter_map do |raw_version, raw_listing|
          version = T.cast(raw_version, Object)
          listing = parse_version_listing(T.cast(raw_listing, Object))
          next if listing.deprecated?
          unless version.is_a?(String) || version.is_a?(Integer)
            raise TypeError, "Registry version must be a string or integer"
          end

          VersionListing.new(version: version, listing: listing)
        end
      end

      sig { params(version: T.nilable(String)).returns(T::Boolean) }
      def published?(version)
        !!NpmRegistryMetadata.nested_field(@fields["time"], version)
      end

      sig { params(version: T.nilable(VersionKey)).returns(Time) }
      def published_at(version)
        date = NpmRegistryMetadata.nested_field(@fields["time"], version)
        raise TypeError, "Registry publication time must be a string" unless date.is_a?(String)

        Time.parse(date)
      end

      private

      sig { params(fields: Object).returns(Listing) }
      def parse_version_listing(fields)
        case fields
        when Hash then Listing.new(T.let(fields, JsonObject))
        when String then Listing.new(fields)
        when Array then raise TypeError, "Registry version details cannot be indexed by a string"
        else raise NoMethodError, "Registry version details cannot be indexed"
        end
      end
    end
  end
end
