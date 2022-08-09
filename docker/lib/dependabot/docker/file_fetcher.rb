# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(/dockerfile/i) } or
          filenames.any? { |f| f.match?(/^[^\.]+\.ya?ml$/i) }
      end

      def self.required_files_message
        "Repo must contain a Dockerfile or Kubernetes YAML files."
      end

      private

      def kubernetes_enabled?
        options.key?(:kubernetes_updates) && options[:kubernetes_updates]
      end

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_dockerfiles
        if kubernetes_enabled?
          fetched_files += correctly_encoded_yamlfiles
        end

        return fetched_files if fetched_files.any?

        if !kubernetes_enabled? && incorrectly_encoded_dockerfiles.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "Dockerfile")
          )
        elsif incorrectly_encoded_dockerfiles.none? && incorrectly_encoded_yamlfiles.none?
          raise(
            Dependabot::DependabotError,
            "Found neither Kubernetes YAML nor Dockerfiles in #{directory}"
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
          select { |f| f.type == "file" && f.name.match?(/dockerfile/i) }.
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
          select { |f| f.type == "file" && f.name.match?(/^[^\.]+\.ya?ml$/i) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def likely_kubernetes_resource?(resource)
        # Heuristic for being a Kubernetes resource. We could make this tighter but this probably works well.
        resource.is_a?(::Hash) && resource.key?("apiVersion") && resource.key?("kind")
      end

      def correctly_encoded_yamlfiles
        candidate_files = yamlfiles.select { |f| f.content.valid_encoding? }
        candidate_files.select do |f|
          begin
            # This doesn't handle multi-resource files, but it shouldn't matter, since the first resource
            # in a multi-resource file had better be a valid k8s resource
            content = ::YAML.safe_load(f.content, aliases: true)
            likely_kubernetes_resource?(content)
          rescue ::Psych::Exception
            false
          end
        end
      end

      def incorrectly_encoded_yamlfiles
        yamlfiles.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
