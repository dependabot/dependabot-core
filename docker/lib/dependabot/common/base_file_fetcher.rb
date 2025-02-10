require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module DockerCommon
    class BaseFileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { abstract.returns(Regexp) }
      def self.filename_regex
        raise NotImplementedError, "#{self.class.name} must implement .filename_regex"
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(filename_regex) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_files.none?
          raise Dependabot::DependencyFileNotFound.new(
            File.join(directory, default_file_name),
            "No #{file_type} files found in #{directory}"
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            T.must(incorrectly_encoded_files.first).path
          )
        end
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def dockerfiles
        @dockerfiles ||= T.let(fetch_candidate_files, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[DependencyFile]) }
      def fetch_candidate_files
        repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(self.class.filename_regex) }
          .map { |f| fetch_file_from_host(f.name) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def correctly_encoded_files
        dockerfiles.select { |f| f.content&.valid_encoding? }
      end

      sig { returns(T::Array[DependencyFile]) }
      def incorrectly_encoded_files
        dockerfiles.reject { |f| f.content&.valid_encoding? }
      end

      sig { abstract.returns(String) }
      def default_file_name
        raise NotImplementedError, "#{self.class.name} must implement #default_file_name"
      end

      sig { abstract.returns(String) }
      def file_type
        raise NotImplementedError, "#{self.class.name} must implement #file_type"
      end
    end
  end
end
