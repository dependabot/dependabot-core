# frozen_string_literal: true

require "dependabot/dependency_file"

module Dependabot
  module FileUpdaters
    class VendorUpdater
      def initialize(repo_contents_path:, vendor_dir:)
        @repo_contents_path = repo_contents_path
        @vendor_dir = vendor_dir
      end

      # Returns changed files in the vendor/cache folder
      #
      # @param base_directory [String] Update config base directory
      # @return [Array<Dependabot::DependencyFile>]
      def updated_vendor_cache_files(base_directory:)
        return [] unless repo_contents_path && vendor_dir

        Dir.chdir(repo_contents_path) do
          # rubocop:disable Performance/DeletePrefix
          relative_dir = Pathname.new(base_directory).sub(%r{\A/}, "").join(vendor_dir)
          # rubocop:enable Performance/DeletePrefix

          status = SharedHelpers.run_shell_command(
            "git status --untracked-files all --porcelain v1 #{relative_dir}",
            fingerprint: "git status --untracked-files all --porcelain v1 <relative_dir>"
          )
          changed_paths = status.split("\n").map(&:split)
          changed_paths.map do |type, path|
            # The following types are possible to be returned:
            # M = Modified = Default for DependencyFile
            # D = Deleted
            # ?? = Untracked = Created
            operation = Dependabot::DependencyFile::Operation::UPDATE
            operation = Dependabot::DependencyFile::Operation::DELETE if type == "D"
            operation = Dependabot::DependencyFile::Operation::CREATE if type == "??"
            encoding = ""
            encoded_content = File.read(path) unless operation == Dependabot::DependencyFile::Operation::DELETE
            if binary_file?(path)
              encoding = Dependabot::DependencyFile::ContentEncoding::BASE64
              if operation != Dependabot::DependencyFile::Operation::DELETE
                encoded_content = Base64.encode64(encoded_content)
              end
            end

            project_root =
              Pathname.new(File.expand_path(File.join(Dir.pwd, base_directory)))
            file_path =
              Pathname.new(path).expand_path.relative_path_from(project_root)

            Dependabot::DependencyFile.new(
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

      TEXT_ENCODINGS = %w(us-ascii utf-8).freeze

      attr_reader :repo_contents_path, :vendor_dir

      def binary_file?(path)
        return false unless File.exist?(path)

        command = SharedHelpers.escape_command("file -b --mime-encoding #{path}")
        encoding = `#{command}`.strip

        !TEXT_ENCODINGS.include?(encoding)
      end
    end
  end
end
