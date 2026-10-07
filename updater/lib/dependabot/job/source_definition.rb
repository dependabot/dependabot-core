# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/source"

module Dependabot
  class Job
    # Parsed representation of the repository source from the job definition.
    class SourceDefinition < T::ImmutableStruct
      extend T::Sig

      const :provider, String
      const :repo, String
      const :directory, T.nilable(String)
      const :directories, T.nilable(T::Array[String])
      const :branch, T.nilable(String)
      const :commit, T.nilable(String)
      const :hostname, T.nilable(String)
      const :api_endpoint, T.nilable(String)

      sig { params(hash: T::Hash[String, Object]).returns(SourceDefinition) }
      def self.from_hash(hash)
        new(
          provider: required_string(hash, "provider"),
          repo: required_string(hash, "repo"),
          directory: normalized_directory(hash["directory"]),
          directories: normalized_directories(hash["directories"]),
          branch: optional_string(hash["branch"]),
          commit: optional_string(hash["commit"]),
          hostname: optional_string(hash["hostname"]),
          api_endpoint: optional_string(hash["api-endpoint"])
        )
      end

      sig { returns(Dependabot::Source) }
      def to_source
        Dependabot::Source.new(
          provider: provider,
          repo: repo,
          directory: directory,
          directories: directories,
          branch: branch,
          commit: commit,
          hostname: hostname,
          api_endpoint: api_endpoint
        )
      end

      sig { params(hash: T::Hash[String, Object], key: String).returns(String) }
      def self.required_string(hash, key)
        value = hash.fetch(key)
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :required_string

      sig { params(value: T.nilable(Object)).returns(T.nilable(String)) }
      def self.optional_string(value)
        value if value.is_a?(String)
      end
      private_class_method :optional_string

      sig { params(value: T.nilable(Object)).returns(T.nilable(String)) }
      def self.normalized_directory(value)
        return unless value.is_a?(String)

        normalize_path(value)
      end
      private_class_method :normalized_directory

      sig { params(value: T.nilable(Object)).returns(T.nilable(T::Array[String])) }
      def self.normalized_directories(value)
        return unless value.is_a?(Array)
        return unless value.all?(String)

        value.map { |directory| normalize_path(T.cast(directory, String)) }
      end
      private_class_method :normalized_directories

      sig { params(directory: String).returns(String) }
      def self.normalize_path(directory)
        normalized = Pathname.new(directory).cleanpath.to_s
        normalized.start_with?("/") ? normalized : "/#{normalized}"
      end
      private_class_method :normalize_path
    end
  end
end
