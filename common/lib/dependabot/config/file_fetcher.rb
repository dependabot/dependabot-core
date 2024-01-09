# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers/base"
require "dependabot/config/file"

module Dependabot
  module Config
    class FileFetcher < FileFetchers::Base
      extend T::Sig

      CONFIG_FILE_PATHS = T.let(%w(.github/dependabot.yml .github/dependabot.yaml).freeze, T::Array[String])

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        CONFIG_FILE_PATHS.any? { |file| filenames.include?(file) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain either a #{CONFIG_FILE_PATHS.join(' or a ')} file"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def config_file
        @config_file ||= T.let(files.first, T.nilable(Dependabot::DependencyFile))
      end

      private

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[Dependabot::DependencyFile])

        CONFIG_FILE_PATHS.each do |file|
          fn = Pathname.new("/#{file}").relative_path_from(directory)

          begin
            config_file = fetch_file_from_host(fn)
            if config_file
              fetched_files << config_file
              break
            end
          rescue DependencyFileNotFound
            next
          end
        end

        unless self.class.required_files_in?(fetched_files.map(&:name))
          raise DependencyFileNotFound.new(nil, self.class.required_files_message)
        end

        fetched_files
      end
    end
  end
end
