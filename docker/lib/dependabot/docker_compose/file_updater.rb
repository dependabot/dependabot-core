# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"
require "dependabot/common/file_updater_helper"

module Dependabot
  module DockerCompose
    class FileUpdater < Dependabot::FileUpdaters::Base
      include Dependabot::Docker::FileUpdaterHelper

      IMAGE_REGEX = /image:\s*/

      def self.updated_files_regex
        [/docker-compose\.yml/i]
      end

      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: updated_dockercompose_file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency
        # docker-compose.yml files will only ever be updating
        # a single dependency
        dependencies.first
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No docker-compose.yml file!"
      end

      def updated_dockercompose_file_content(file)
        updated_content =
          if specified_with_digest?(file)
            update_digest_and_tag(file)
          else
            update_tag(file)
          end

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      def digest_and_tag_regex(digest)
        /^\s*#{IMAGE_REGEX}\s+.*@#{digest}/
      end

      def tag_regex(declaration)
        escaped_declaration = Regexp.escape(declaration)

        %r{^\s*#{IMAGE_REGEX}\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)}
      end
    end
  end
end

Dependabot::FileUpdaters.register(
  "docker_compose",
  Dependabot::DockerCompose::FileUpdater
)
