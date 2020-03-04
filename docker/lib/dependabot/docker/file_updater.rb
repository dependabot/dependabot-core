# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Docker
    class FileUpdater < Dependabot::FileUpdaters::Base
      FROM_REGEX = /[Ff][Rr][Oo][Mm]/.freeze

      def self.updated_files_regex
        [/dockerfile/i]
      end

      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency
        # Dockerfiles will only ever be updating a single dependency
        dependencies.first
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No file!"
      end

      def file_content(file)
        updated_content = update_tag(file)

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      def update_digest_and_tag(file)
        old_declaration_regex = /^#{FROM_REGEX}\s+.*@#{old_digest(file)}/

        file.content.gsub(old_declaration_regex) do |old_dec|
          old_dec.
            gsub("@#{old_digest(file)}", "@#{new_digest(file)}").
            gsub(":#{dependency.previous_version}",
                 ":#{dependency.version}")
        end
      end

      def update_tag(file)
        return unless old_tag(file)

        img_data =
          if private_registry_url(file) then "#{private_registry_url(file)}/"
          else ""
          end
        img_data += dependency.name.to_s

        tag_var = file.content.match(/repository: #{img_data}\n + (tag: [^\n]+)\n/)
        new_tag_var = tag_var.to_s.gsub(Regexp.last_match(1), "tag: \"#{new_tag(file)}\"")
        file.content.gsub(tag_var.to_s, new_tag_var.to_s)
      end

      def specified_with_digest?(file)
        dependency.
          requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source)[:digest]
      end

      def new_digest(file)
        return unless specified_with_digest?(file)

        dependency.requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source).fetch(:digest)
      end

      def old_digest(file)
        return unless specified_with_digest?(file)

        dependency.previous_requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source).fetch(:digest)
      end

      def new_tag(file)
        dependency.requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source)[:tag]
      end

      def old_tag(file)
        dependency.previous_requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source)[:tag]
      end

      def private_registry_url(file)
        dependency.requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source)[:registry]
      end
    end
  end
end

Dependabot::FileUpdaters.register("docker", Dependabot::Docker::FileUpdater)
