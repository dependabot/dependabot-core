# typed: strict
# frozen_string_literal: true

require "base64"
require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/errors"

module Dependabot
  class FetchedFiles
    extend T::Sig

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :dependency_files

    sig { returns(String) }
    attr_reader :base_commit_sha

    # Maps a directory to the non-fatal fetch error encountered while fetching it
    # (e.g. an unresolvable path dependency for a graph job). The directory is
    # still reported, but with a skipped snapshot describing the failure.
    sig { returns(T::Hash[String, Dependabot::DependabotError]) }
    attr_reader :directory_fetch_errors

    sig do
      params(
        dependency_files: T::Array[Dependabot::DependencyFile],
        base_commit_sha: String,
        directory_fetch_errors: T::Hash[String, Dependabot::DependabotError]
      ).void
    end
    def initialize(dependency_files:, base_commit_sha:, directory_fetch_errors: {})
      @dependency_files = dependency_files
      @base_commit_sha = base_commit_sha
      @directory_fetch_errors = directory_fetch_errors
    end

    # Rehydrates a FetchedFiles from the JSON artifact produced by #serialize.
    sig { params(serialized: String).returns(Dependabot::FetchedFiles) }
    def self.deserialize(serialized)
      data = T.cast(JSON.parse(serialized), T::Hash[String, Object])

      dependency_files = T.cast(data.fetch("base64_dependency_files"), T::Array[T::Hash[String, Object]])
                          .map { |file_hash| dependency_file_from(file_hash) }

      directory_fetch_errors = T.cast(data["directory_fetch_errors"] || {}, T::Hash[String, T::Hash[String, Object]])
                                .transform_values { |error_hash| error_from(error_hash) }

      new(
        dependency_files: dependency_files,
        base_commit_sha: T.cast(data.fetch("base_commit_sha"), String),
        directory_fetch_errors: directory_fetch_errors
      )
    end

    sig { params(file_hash: T::Hash[String, Object]).returns(Dependabot::DependencyFile) }
    def self.dependency_file_from(file_hash)
      file = Dependabot::DependencyFile.new(
        name: T.cast(file_hash["name"], String),
        content: T.cast(file_hash["content"], T.nilable(String)),
        directory: T.cast(file_hash["directory"], String),
        type: T.cast(file_hash["type"], String),
        support_file: T.cast(file_hash["support_file"], T::Boolean),
        content_encoding: T.cast(file_hash["content_encoding"], String),
        deleted: T.cast(file_hash["deleted"], T::Boolean),
        operation: T.cast(file_hash["operation"], String),
        mode: T.cast(file_hash["mode"], T.nilable(String)),
        symlink_target: T.cast(file_hash["symlink_target"], T.nilable(String))
      )

      # Non-binary content was Base64-encoded for safe transport; binary files stay encoded.
      file.content = Base64.decode64(T.must(file.content)).force_encoding("utf-8") unless file.binary? && !file.deleted?

      file
    end
    private_class_method :dependency_file_from

    sig { params(error_hash: T::Hash[String, Object]).returns(Dependabot::DependabotError) }
    def self.error_from(error_hash)
      case error_hash["class"]
      when "Dependabot::PathDependenciesNotReachable"
        Dependabot::PathDependenciesNotReachable.new(T.cast(error_hash["dependencies"] || [], T::Array[String]))
      else
        Dependabot::DependabotError.new(T.cast(error_hash["message"], T.nilable(String)))
      end
    end
    private_class_method :error_from

    # Serializes the persisted files so a clone-less update container can rehydrate them
    # instead of re-fetching. Uses the existing base64_dependency_files contract, with
    # directory_fetch_errors as an optional additive key.
    sig { returns(String) }
    def serialize
      payload = T.let(
        {
          "base_commit_sha" => base_commit_sha,
          "base64_dependency_files" => dependency_files.map { |file| base64_file_hash(file) }
        },
        T::Hash[String, Object]
      )

      unless directory_fetch_errors.empty?
        payload["directory_fetch_errors"] = directory_fetch_errors.transform_values { |error| error_to_h(error) }
      end

      JSON.generate(payload)
    end

    private

    sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, Object]) }
    def base64_file_hash(file)
      hash = file.to_h
      # Binary files are already Base64-encoded via content_encoding; only encode the rest.
      hash["content"] = Base64.encode64(T.must(file.content)) unless file.binary?
      hash
    end

    sig { params(error: Dependabot::DependabotError).returns(T::Hash[String, Object]) }
    def error_to_h(error)
      hash = T.let({ "class" => error.class.name, "message" => error.message }, T::Hash[String, Object])
      hash["dependencies"] = error.dependencies if error.is_a?(Dependabot::PathDependenciesNotReachable)
      hash
    end
  end
end
