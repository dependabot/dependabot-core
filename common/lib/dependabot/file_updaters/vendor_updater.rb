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
          relative_dir = Pathname.new(vendor_dir).relative_path_from(
            repo_contents_path
          )

          status = SharedHelpers.run_shell_command(
            "git status --untracked-files=all --porcelain=v1 #{relative_dir}"
          )
          changed_paths = status.split("\n").map { |l| l.split(" ") }
          changed_paths.map do |type, path|
            deleted = type == "D"
            encoding = ""
            encoded_content = File.read(path) unless deleted
            if binary_file?(path)
              encoding = Dependabot::DependencyFile::ContentEncoding::BASE64
              encoded_content = Base64.encode64(encoded_content) unless deleted
            end

            project_root =
              Pathname.new(File.expand_path(File.join(Dir.pwd, base_directory)))
            file_path =
              Pathname.new(path).expand_path.relative_path_from(project_root)

            Dependabot::DependencyFile.new(
              name: file_path.to_s,
              content: encoded_content,
              directory: base_directory,
              deleted: deleted,
              content_encoding: encoding
            )
          end
        end
      end

      private

      BINARY_ENCODINGS = %w(application/x-tarbinary binary).freeze

      attr_reader :repo_contents_path, :vendor_dir

      def binary_file?(path)
        return false unless File.exist?(path)

        encoding = `file -b --mime-encoding #{path}`.strip

        BINARY_ENCODINGS.include?(encoding)
      end
    end
  end
end
