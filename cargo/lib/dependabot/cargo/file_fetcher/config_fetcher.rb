# typed: strict
# frozen_string_literal: true

require "dependabot/cargo/file_fetcher"

module Dependabot
  module Cargo
    class FileFetcher < Dependabot::FileFetchers::Base
      class ConfigFetcher
        extend T::Sig

        sig { params(fetcher: Dependabot::Cargo::FileFetcher).void }
        def initialize(fetcher:)
          @fetcher = fetcher
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def fetch_from_parent_dirs
          return nil if directory.empty?

          # Count directory depth to determine how many levels to search up
          depth = directory.split("/").count { |s| !s.empty? }
          return nil if depth.zero?

          # Try each parent directory level
          depth.times do |i|
            parent_path = ([".."] * (i + 1)).join("/")
            config = try_fetch_config_at_path(parent_path)
            return config if config
          end

          nil
        end

        private

        sig { returns(Dependabot::Cargo::FileFetcher) }
        attr_reader :fetcher

        sig { returns(String) }
        def directory
          fetcher.send(:directory)
        end

        sig { params(parent_path: String).returns(T.nilable(Dependabot::DependencyFile)) }
        def try_fetch_config_at_path(parent_path)
          [".cargo/config.toml", ".cargo/config"].each do |config_name|
            config = fetcher.send(
              :fetch_file_from_host,
              File.join(parent_path, config_name),
              fetch_submodules: false
            )
            config.support_file = true
            config.name = ".cargo/config.toml"
            return config
          rescue Dependabot::DependencyFileNotFound
            next
          end
          nil
        end
      end
    end
  end
end
