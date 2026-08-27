# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"

module Dependabot
  module Package
    class NpmRegistryPackage < T::ImmutableStruct
      extend T::Sig

      ObjectHash = T.type_alias { T::Hash[String, Object] }
      VersionFilter = T.type_alias { T.proc.params(version: String).returns(T::Boolean) }

      class Repository < T::ImmutableStruct
        extend T::Sig

        const :git, T::Boolean
        const :url, T.nilable(String), default: nil
        const :type, T.nilable(String), default: nil

        sig { returns(T::Boolean) }
        def git?
          git
        end
      end

      class Release < T::ImmutableStruct
        extend T::Sig

        const :version, String
        const :released_at, T.nilable(Time), default: nil
        const :node_requirement, T.nilable(String), default: nil
        const :repository, T.nilable(Repository), default: nil
        const :details, ObjectHash

        sig { returns(String) }
        def package_type
          repository&.git? ? "git" : "npm"
        end
      end

      const :releases, T::Hash[String, Release]
      const :dist_tags, T.nilable(T::Hash[String, String]), default: nil

      sig { params(json: String, version_filter: VersionFilter).returns(NpmRegistryPackage) }
      def self.from_json(json, &version_filter)
        parsed = T.cast(JSON.parse(json), Object)
        package = object_hash(parsed, "npm registry package")

        versions = package["versions"]
        times = package["time"]
        dist_tags = package["dist-tags"]

        release_details = versions.nil? ? {} : object_hash(versions, "versions")
        accepted_versions = T.let({}, T::Hash[String, T::Boolean])
        release_details.each_key do |version|
          accepted_versions[version] = true if yield(version)
        end

        release_times = if times.nil?
                          {}
                        else
                          string_map(times, "time", included_keys: accepted_versions)
                        end

        releases = T.let({}, T::Hash[String, Release])
        release_details.each do |version, details|
          next unless accepted_versions.key?(version)

          releases[version] = parse_release(
            version: version,
            details: details,
            released_at: release_times[version]
          )
        end

        new(
          releases: releases,
          dist_tags: dist_tags.nil? ? nil : string_map(dist_tags, "dist-tags")
        )
      end

      sig do
        params(
          version: String,
          details: Object,
          released_at: T.nilable(String)
        ).returns(Release)
      end
      def self.parse_release(version:, details:, released_at:)
        details_hash = object_hash(details, "version #{version} details")

        Release.new(
          version: version,
          released_at: released_at && Time.parse(released_at),
          node_requirement: parse_node_requirement(details_hash, version),
          repository: parse_repository(details_hash["repository"], version),
          details: details_hash
        )
      end
      private_class_method :parse_release

      sig { params(details: ObjectHash, version: String).returns(T.nilable(String)) }
      def self.parse_node_requirement(details, version)
        engines = details["engines"]
        return unless engines.is_a?(Hash)

        engines_hash = object_hash(engines, "version #{version} engines")
        optional_string(
          engines_hash["node"],
          "version #{version} engines.node"
        )
      end
      private_class_method :parse_node_requirement

      sig { params(value: T.nilable(Object), version: String).returns(T.nilable(Repository)) }
      def self.parse_repository(value, version)
        case value
        when nil
          nil
        when String
          Repository.new(url: value, git: value.start_with?("git+"))
        when Hash
          repository = object_hash(value, "version #{version} repository")
          url = optional_string(repository["url"], "version #{version} repository.url")
          type = optional_string(repository["type"], "version #{version} repository.type")

          Repository.new(
            url: url,
            type: type,
            git: type == "git"
          )
        else
          raise TypeError, "version #{version} repository must be a string or object"
        end
      end
      private_class_method :parse_repository

      sig { params(value: Object, context: String).returns(ObjectHash) }
      def self.object_hash(value, context)
        raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

        result = T.let({}, ObjectHash)
        value.each do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          raise TypeError, "#{context} keys must be strings" unless key.is_a?(String)

          result[key] = T.cast(raw_value, Object)
        end
        result
      end
      private_class_method :object_hash

      sig do
        params(
          value: Object,
          context: String,
          included_keys: T.nilable(T::Hash[String, T::Boolean])
        ).returns(T::Hash[String, String])
      end
      def self.string_map(value, context, included_keys: nil)
        result = T.let({}, T::Hash[String, String])
        object_hash(value, context).each do |key, raw_value|
          next if included_keys && !included_keys.key?(key)

          raise TypeError, "#{context} values must be strings" unless raw_value.is_a?(String)

          result[key] = raw_value
        end
        result
      end
      private_class_method :string_map

      sig { params(value: T.nilable(Object), context: String).returns(T.nilable(String)) }
      def self.optional_string(value, context)
        return if value.nil?
        return value if value.is_a?(String)

        raise TypeError, "#{context} must be a string"
      end
      private_class_method :optional_string
    end
  end
end
