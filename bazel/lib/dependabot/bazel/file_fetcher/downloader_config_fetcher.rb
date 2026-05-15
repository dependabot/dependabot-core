# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Fetches downloader configuration files referenced in .bazelrc.
      # Parses .bazelrc for --downloader_config flags and fetches those files.
      class DownloaderConfigFetcher
        extend T::Sig

        sig { params(fetcher: FileFetcher).void }
        def initialize(fetcher:)
          @fetcher = fetcher
        end

        sig { returns(T::Array[DependencyFile]) }
        def fetch_downloader_config_files
          bazelrc_file = @fetcher.send(:fetch_file_if_present, ".bazelrc")
          return [] unless bazelrc_file

          config_paths = extract_downloader_config_paths(bazelrc_file)
          files = T.let([], T::Array[DependencyFile])

          config_paths.each do |path|
            fetched_file = @fetcher.send(:fetch_file_if_present, path)
            files << fetched_file if fetched_file
          rescue Dependabot::DependencyFileNotFound
            Dependabot.logger.warn(
              "Downloader config file '#{path}' referenced in .bazelrc but not found in repository"
            )
          end

          files
        end

        private

        sig { returns(FileFetcher) }
        attr_reader :fetcher

        sig { params(bazelrc_file: DependencyFile).returns(T::Array[String]) }
        def extract_downloader_config_paths(bazelrc_file)
          content = T.must(bazelrc_file.content)
          extract_downloader_config_flags(content).reject(&:empty?).uniq
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_downloader_config_flags(content)
          content.scan(/--downloader_config[=\s]+(\S+)/).flatten
        end
      end
    end
  end
end
