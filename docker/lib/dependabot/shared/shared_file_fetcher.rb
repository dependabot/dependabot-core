# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/shared/utils/helpers"

module Dependabot
  module Shared
    class SharedFileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      abstract!

      YAML_REGEXP = /^[^\.].*\.ya?ml$/i

      sig { abstract.returns(Regexp) }
      def self.filename_regex; end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(filename_regex) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files + correctly_encoded_yamlfiles
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
            content = YAML.safe_load(T.must(f.content), aliases: true)
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

      sig do
        params(
          incorrectly_encoded_files: T::Array[Dependabot::DependencyFile]
        ).returns(T.noreturn)
      end
      def raise_appropriate_error(
        incorrectly_encoded_files = []
      )
        if incorrectly_encoded_files.none? && incorrectly_encoded_yamlfiles.none?
          raise Dependabot::DependencyFileNotFound.new(
            File.join(directory, "Dockerfile"),
            "No Dockerfiles nor Kubernetes YAML found in #{directory}"
          )
        end

        invalid_files = incorrectly_encoded_files.any? ? incorrectly_encoded_files : incorrectly_encoded_yamlfiles
        raise Dependabot::DependencyFileNotParseable, T.must(invalid_files.first).path
      end

      sig { returns(T::Array[DependencyFile]) }
      def yamlfiles
        @yamlfiles ||= T.let(
          repo_contents(raise_errors: false)
            .select { |f| f.type == "file" && f.name.match?(YAML_REGEXP) }
            .map do |f|
              fetched = fetch_file_from_host(f.name)
              # The YAML parser used doesn't properly handle a byte-order-mark (BOM) and it can cause failures in
              # unexpected ways.  That BOM is removed here to allow regular updates to proceed.
              fetched.content = T.must(fetched.content).delete_prefix("\uFEFF")
              fetched
            end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      private

      sig { params(resource: Object).returns(T.nilable(T::Boolean)) }
      def likely_kubernetes_resource?(resource)
        # Heuristic for being a Kubernetes resource. We could make this tighter but this probably works well.
        resource.is_a?(::Hash) && resource.key?("apiVersion") && resource.key?("kind")
      end

      sig { abstract.returns(String) }
      def default_file_name; end

      sig { abstract.returns(String) }
      def file_type; end
    end
  end
end
