# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/bundler/native_helpers"

module Dependabot
  module Bundler
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/gemfile_updater"
      require_relative "file_updater/gemspec_updater"
      require_relative "file_updater/lockfile_updater"

      def self.updated_files_regex
        [
          /^Gemfile$/,
          /^Gemfile\.lock$/,
          /^gems\.rb$/,
          /^gems\.locked$/,
          /^*\.gemspec$/
        ]
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def updated_dependency_files
        updated_files = []

        if gemfile && file_changed?(gemfile)
          updated_files <<
            updated_file(
              file: gemfile,
              content: updated_gemfile_content(gemfile)
            )
        end

        if lockfile && dependencies.any?(&:appears_in_lockfile?)
          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)
        end

        top_level_gemspecs.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(file: file, content: updated_gemspec_content(file))
        end

        evaled_gemfiles.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(file: file, content: updated_gemfile_content(file))
        end

        check_updated_files(updated_files)

        base_dir = updated_files.first.directory
        updated_vendor_cache_files(base_directory: base_dir).each do |file|
          updated_files << file
        end

        updated_files
      end
      # rubocop:enable Metrics/PerceivedComplexity

      private

      # Dynamically fetch the vendor cache folder from bundler
      def vendor_cache_dir
        return @vendor_cache_dir if defined?(@vendor_cache_dir)

        @vendor_cache_dir =
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "vendor_cache_dir",
            args: {
              dir: repo_contents_path
            }
          )
      end

      # Returns changed files in the vendor/cache folder
      #
      # @param base_directory [String] Update config base directory
      # @return [Array<Dependabot::DependencyFile>]
      def updated_vendor_cache_files(base_directory:)
        return [] unless repo_contents_path && vendor_cache_dir

        Dir.chdir(repo_contents_path) do
          relative_dir = vendor_cache_dir.sub("#{repo_contents_path}/", "")
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
            Dependabot::DependencyFile.new(
              name: path,
              content: encoded_content,
              directory: base_directory,
              deleted: deleted,
              content_encoding: encoding
            )
          end
        end
      end

      # notable filenames without a reliable extension:
      TEXT_FILE_NAMES = [
        "Gemfile",
        "Gemfile.lock",
        ".bundlecache",
        ".gitignore"
      ].freeze

      TEXT_FILE_EXTS = [
        # code
        ".rb",
        ".erb",
        ".gemspec",
        ".js",
        ".html",
        # config
        ".json",
        ".xml",
        ".toml",
        ".yaml",
        ".yml",
        # docs
        ".md",
        ".txt"
      ].freeze

      def binary_file?(path)
        return false if TEXT_FILE_NAMES.include?(File.basename(path))
        return false if TEXT_FILE_EXTS.include?(File.extname(path))

        true
      end

      def check_required_files
        file_names = dependency_files.map(&:name)

        if lockfile && !gemfile
          raise "A Gemfile must be provided if a lockfile is!"
        end

        return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return if gemfile

        raise "A gemspec or Gemfile must be provided!"
      end

      def check_updated_files(updated_files)
        return if updated_files.reject { |f| dependency_files.include?(f) }.any?

        raise "No files have changed!"
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile") ||
                     get_original_file("gems.rb")
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock") ||
                      get_original_file("gems.locked")
      end

      def evaled_gemfiles
        @evaled_gemfiles ||=
          dependency_files.
          reject { |f| f.name.end_with?(".gemspec") }.
          reject { |f| f.name.end_with?(".specification") }.
          reject { |f| f.name.end_with?(".lock") }.
          reject { |f| f.name.end_with?(".ruby-version") }.
          reject { |f| f.name == "Gemfile" }.
          reject { |f| f.name == "gems.rb" }.
          reject { |f| f.name == "gems.locked" }
      end

      def updated_gemfile_content(file)
        GemfileUpdater.new(
          dependencies: dependencies,
          gemfile: file
        ).updated_gemfile_content
      end

      def updated_gemspec_content(gemspec)
        GemspecUpdater.new(
          dependencies: dependencies,
          gemspec: gemspec
        ).updated_gemspec_content
      end

      def updated_lockfile_content
        @updated_lockfile_content ||=
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          ).updated_lockfile_content
      end

      def top_level_gemspecs
        dependency_files.
          select { |file| file.name.end_with?(".gemspec") }.
          reject(&:support_file?)
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("bundler", Dependabot::Bundler::FileUpdater)
