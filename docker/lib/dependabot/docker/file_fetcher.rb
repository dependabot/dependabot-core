# frozen_string_literal: true

require "dependabot/docker/utils/helpers"
require "dependabot/experiments"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::FileFetchers::Base
      YAML_REGEXP = /^[^\.]+\.ya?ml$/i
      DOCKER_REGEXP = /dockerfile/i

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(DOCKER_REGEXP) } or
          filenames.any? { |f| f.match?(YAML_REGEXP) }
      end

      def self.required_files_message
        "Repo must contain a Dockerfile or Kubernetes YAML files."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_dockerfiles
        fetched_files += correctly_encoded_yamlfiles

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_dockerfiles.none? && incorrectly_encoded_yamlfiles.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "Dockerfile"),
            "No Dockerfiles nor Kubernetes YAML found in #{directory}"
          )
        elsif incorrectly_encoded_dockerfiles.none?
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_yamlfiles.first.path
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_dockerfiles.first.path
          )
        end
      end

      def dockerfiles
        @dockerfiles ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(DOCKER_REGEXP) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_dockerfiles
        dockerfiles.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_dockerfiles
        dockerfiles.reject { |f| f.content.valid_encoding? }
      end

      def yamlfiles
        @yamlfiles ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(YAML_REGEXP) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def likely_kubernetes_resource?(resource)
        # Heuristic for being a Kubernetes resource. We could make this tighter but this probably works well.
        resource.is_a?(::Hash) && resource.key?("apiVersion") && resource.key?("kind")
      end

      def correctly_encoded_yamlfiles
        candidate_files = yamlfiles.select { |f| f.content.valid_encoding? }
        candidate_files.select do |f|
          if f.type == "file" && Utils.likely_helm_chart?(f)
            true
          else
            # This doesn't handle multi-resource files, but it shouldn't matter, since the first resource
            # in a multi-resource file had better be a valid k8s resource
            content = ::YAML.safe_load(f.content, aliases: true)
            likely_kubernetes_resource?(content)
          end
        rescue ::Psych::Exception
          false
        end
      end

      def incorrectly_encoded_yamlfiles
        yamlfiles.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
