# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/docker/utils/helpers"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      YAML_REGEXP = /^[^\.].*\.ya?ml$/i
      DOCKER_REGEXP = /(docker|container)file/i

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(DOCKER_REGEXP) } or
          filenames.any? { |f| f.match?(YAML_REGEXP) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Dockerfile, Containerfile, or Kubernetes YAML files."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_dockerfiles
        fetched_files += correctly_encoded_yamlfiles

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_dockerfiles.none? && incorrectly_encoded_yamlfiles.none?
          raise Dependabot::DependencyFileNotFound.new(
            File.join(directory, "Dockerfile"),
            "No Dockerfiles nor Kubernetes YAML found in #{directory}"
          )
        elsif incorrectly_encoded_dockerfiles.none?
          raise(
            Dependabot::DependencyFileNotParseable,
            T.must(incorrectly_encoded_yamlfiles.first).path
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            T.must(incorrectly_encoded_dockerfiles.first).path
          )
        end
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def dockerfiles
        @dockerfiles ||= T.let(fetch_dockerfiles, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_dockerfiles
        repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(DOCKER_REGEXP) }
          .map { |f| fetch_file_from_host(f.name) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def correctly_encoded_dockerfiles
        dockerfiles.select { |f| f.content&.valid_encoding? }
      end

      sig { returns(T::Array[DependencyFile]) }
      def incorrectly_encoded_dockerfiles
        dockerfiles.reject { |f| f.content&.valid_encoding? }
      end

      sig { returns(T::Array[DependencyFile]) }
      def yamlfiles
        @yamlfiles ||= T.let(
          repo_contents(raise_errors: false)
                  .select { |f| f.type == "file" && f.name.match?(YAML_REGEXP) }
                  .map { |f| fetch_file_from_host(f.name) },
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(resource: Object).returns(T.nilable(T::Boolean)) }
      def likely_kubernetes_resource?(resource)
        # Heuristic for being a Kubernetes resource. We could make this tighter but this probably works well.
        resource.is_a?(::Hash) && resource.key?("apiVersion") && resource.key?("kind")
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def correctly_encoded_yamlfiles
        candidate_files = yamlfiles.select { |f| f.content&.valid_encoding? }
        candidate_files.select do |f|
          if f.type == "file" && Utils.likely_helm_chart?(f)
            true
          else
            # This doesn't handle multi-resource files, but it shouldn't matter, since the first resource
            # in a multi-resource file had better be a valid k8s resource
            content = ::YAML.safe_load(T.must(f.content), aliases: true)
            likely_kubernetes_resource?(content)
          end
        rescue ::Psych::Exception
          false
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def incorrectly_encoded_yamlfiles
        yamlfiles.reject { |f| f.content&.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
