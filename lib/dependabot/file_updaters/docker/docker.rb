# frozen_string_literal: true

require "docker_registry2"

require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module Docker
      class Docker < Dependabot::FileUpdaters::Base
        FROM_REGEX = /[Ff][Rr][Oo][Mm]/

        def self.updated_files_regex
          [/dockerfile/]
        end

        def updated_dependency_files
          dependency_files.map do |file|
            updated_file(file: file, content: updated_dockerfile_content(file))
          end
        end

        private

        def dependency
          # Dockerfiles will only ever be updating a single dependency
          dependencies.first
        end

        def check_required_files
          # Just check if there are any files at all.
          return if dependency_files.any?
          raise "No Dockerfile!"
        end

        def updated_dockerfile_content(file)
          updated_content =
            if specified_with_digest?(file)
              update_digest(file)
            else
              update_tag(file)
            end

          raise "Expected content to change!" if updated_content == file.content
          updated_content
        end

        def update_digest(file)
          old_declaration_regex = /^#{FROM_REGEX}\s+.*@#{old_digest(file)}/

          file.content.gsub(old_declaration_regex) do |old_dec|
            old_dec.
              gsub("@#{old_digest(file)}", "@#{new_digest(file)}").
              gsub(":#{dependency.previous_version}",
                   ":#{dependency.version}")
          end
        end

        def update_tag(file)
          old_declaration =
            if private_registry_url(file)
              "#{private_registry_url(file)}/"
            else
              ""
            end
          old_declaration += "#{dependency.name}:#{dependency.previous_version}"
          escaped_declaration = Regexp.escape(old_declaration)

          old_declaration_regex = /^#{FROM_REGEX}\s+#{escaped_declaration}/

          file.content.gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(
              ":#{dependency.previous_version}",
              ":#{dependency.version}"
            )
          end
        end

        def specified_with_digest?(file)
          dependency.
            requirements.
            find { |r| r[:file] == file.name }.
            fetch(:source).fetch(:type) == "digest"
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

        def private_registry_url(file)
          dependency.requirements.
            find { |r| r[:file] == file.name }.
            fetch(:source)[:registry]
        end
      end
    end
  end
end
