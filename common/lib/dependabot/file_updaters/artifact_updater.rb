# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"

# This class provides a utility to check for arbitrary modified files within a
# git directory that need to be wrapped as Dependabot::DependencyFile object
# and returned as along with anything managed by the FileUpdater itself.
module Dependabot
  module FileUpdaters
    class ArtifactUpdater
      extend T::Sig
      extend T::Helpers

      # @param repo_contents_path [String, nil] the path we cloned the repository into
      # @param target_directory [String, nil] the path within a project directory we should inspect for changes
      sig { params(repo_contents_path: T.nilable(String), target_directory: T.nilable(String)).void }
      def initialize(repo_contents_path:, target_directory:)
        @repo_contents_path = repo_contents_path
        @target_directory = target_directory
      end

      # Returns any files that have changed within the path composed from:
      #   :repo_contents_path/:base_directory/:target_directory
      #
      # @param base_directory [String] Update config base directory
      # @param only_paths [Array<String>, nil] An optional list of specific paths to check, if this is nil we will
      #                                        return every change we find within the `base_directory`
      # @return [Array<Dependabot::DependencyFile>]
      sig do
        params(base_directory: String, only_paths: T.nilable(T::Array[String]))
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def updated_files(base_directory:, only_paths: nil)
        return [] unless repo_contents_path && target_directory

        Dir.chdir(T.must(repo_contents_path)) do
          # rubocop:disable Performance/DeletePrefix
          relative_dir = Pathname.new(base_directory).sub(%r{\A/}, "").join(T.must(target_directory))
          # rubocop:enable Performance/DeletePrefix

          status = T.let(
            SharedHelpers.run_shell_command(
              "git status --untracked-files all --porcelain v1 #{relative_dir}",
              fingerprint: "git status --untracked-files all --porcelain v1 <relative_dir>"
            ),
            String
          )
          changed_paths = status.split("\n").map(&:split)
          changed_paths.filter_map do |type, path|
            project_root = Pathname.new(File.expand_path(File.join(Dir.pwd, base_directory)))
            file_path = Pathname.new(path).expand_path.relative_path_from(project_root)

            # Skip this file if we are looking for specific paths and this isn't on the list
            next if only_paths && !only_paths.include?(file_path.to_s)

            # The following types are possible to be returned:
            # M = Modified = Default for DependencyFile
            # D = Deleted
            # ?? = Untracked = Created
            operation = Dependabot::DependencyFile::Operation::UPDATE
            operation = Dependabot::DependencyFile::Operation::DELETE if type == "D"
            operation = Dependabot::DependencyFile::Operation::CREATE if type == "??"

            encoded_content, encoding = get_encoded_file_contents(T.must(path), operation)

            create_dependency_file(
              name: file_path.to_s,
              content: encoded_content,
              directory: base_directory,
              operation: operation,
              content_encoding: encoding
            )
          end
        end
      end

      private

      TEXT_ENCODINGS = T.let(%w(us-ascii utf-8).freeze, T::Array[String])

      sig { returns(T.nilable(String)) }
      attr_reader :repo_contents_path
      sig { returns(T.nilable(String)) }
      attr_reader :target_directory

      sig do
        params(
          path: String,
          operation: String
        ).returns([T.nilable(String), String])
      end
      def get_encoded_file_contents(path, operation)
        encoded_content = nil
        encoding = ""

        return encoded_content, encoding if operation == Dependabot::DependencyFile::Operation::DELETE

        encoded_content = File.read(path)

        if binary_file?(path)
          encoding = Dependabot::DependencyFile::ContentEncoding::BASE64
          encoded_content = Base64.encode64(encoded_content)
        end

        [encoded_content, encoding]
      end

      sig { params(path: String).returns(T::Boolean) }
      def binary_file?(path)
        return false unless File.exist?(path)

        command = SharedHelpers.escape_command("file -b --mime-encoding #{path}")
        encoding = `#{command}`.strip

        !TEXT_ENCODINGS.include?(encoding)
      end

      sig do
        overridable
          .params(parameters: T::Hash[Symbol, T.untyped])
          .returns(Dependabot::DependencyFile)
      end
      def create_dependency_file(parameters)
        Dependabot::DependencyFile.new(**T.unsafe(parameters))
      end
    end
  end
end
