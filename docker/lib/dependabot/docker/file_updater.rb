# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Docker
    class FileUpdater < Dependabot::FileUpdaters::Base
      FROM_REGEX = /FROM(\s+--platform\=\S+)?/i.freeze

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
              content: updated_file_content(file)
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

      def updated_file_content(file)
        updated_content = if file.name.match?(/dockerfile|custom/i)
                            if specified_with_digest?(file)
                              update_digest_and_tag(file)
                            else
                              update_tag_docker(file)
                            end
                          else
                            update_tag_template(file)
                          end
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

      def update_tag_docker(file)
        old_tags = old_tags(file)
        return if old_tags.empty?

        modified_content = file.content

        old_tags.each do |old_tag|
          old_declaration =
            if private_registry_url(file) then "#{private_registry_url(file)}/"
            else
              ""
            end
          old_declaration += "#{dependency.name}:#{old_tag}"
          escaped_declaration = Regexp.escape(old_declaration)

          old_declaration_regex =
            %r{^#{FROM_REGEX}\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)}

          modified_content = modified_content.
                             gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(":#{old_tag}", ":#{new_tag(file)}")
          end
        end

        modified_content
      end

      def update_tag_template(file)
        old_tags = old_tags(file)
        return if old_tags.empty?

        modified_content = file.content

        old_tags.each do |old_tag|
          old_declaration =
            if private_registry_url(file) then "#{private_registry_url(file)}/"
            else ""
            end
          old_declaration += dependency.name.to_s
          escaped_declaration = Regexp.escape(old_declaration)
          old_declaration_regex =
            %r{repository:\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)\n\s+
            \s(tag:\s[^\n]+)\n}x

          modified_content = modified_content.
                             gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(
              /(tag:\s#{old_tag})|(tag:\s"#{old_tag}")/,
              "tag:\s#{new_tag(file)}"
            )
          end
        end

        modified_content
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

      def old_tags(file)
        dependency.
          previous_requirements.
          select { |r| r[:file] == file.name }.
          map { |r| r.fetch(:source)[:tag] }
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
