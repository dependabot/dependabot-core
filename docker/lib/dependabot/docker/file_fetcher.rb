# typed: strict
# frozen_string_literal: true

require "dependabot/docker/utils/helpers"
require_relative "../shared/base_file_fetcher"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::Shared::BaseFileFetcher
      extend T::Sig

      YAML_REGEXP = /^[^\.].*\.ya?ml$/i
      DOCKER_REGEXP = /dockerfile|containerfile/i

      sig { override.returns(Regexp) }
      def self.filename_regex
        DOCKER_REGEXP
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Dockerfile, Containerfile, or Kubernetes YAML files."
      end

      private

      sig { override.returns(String) }
      def default_file_name
        "Dockerfile"
      end

      sig { override.returns(String) }
      def file_type
        "Docker"
      end

      # Additional Docker-specific methods for YAML handling
      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = super
        fetched_files += correctly_encoded_yamlfiles

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_yamlfiles.any?
          raise(
            Dependabot::DependencyFileNotParseable,
            T.must(incorrectly_encoded_yamlfiles.first).path
          )
        end

        fetched_files
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
