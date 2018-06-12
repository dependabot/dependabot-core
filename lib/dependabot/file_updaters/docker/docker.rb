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
          [/^Dockerfile$/]
        end

        def updated_dependency_files
          [updated_file(file: dockerfile, content: updated_dockerfile_content)]
        end

        private

        def dependency
          # Dockerfiles will only ever be updating a single dependency
          dependencies.first
        end

        def check_required_files
          %w(Dockerfile).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def updated_dockerfile_content
          updated_content =
            if specified_with_digest?
              update_digest(dockerfile.content)
            else
              update_tag(dockerfile.content)
            end

          if updated_content == dockerfile.content
            raise "Expected content to change!"
          end
          updated_content
        end

        def update_digest(content)
          old_declaration_regex = /^#{FROM_REGEX}\s+.*@#{old_digest}/

          content.gsub(old_declaration_regex) do |old_dec|
            old_dec.
              gsub("@#{old_digest}", "@#{new_digest}").
              gsub(":#{dependency.previous_version}",
                   ":#{dependency.version}")
          end
        end

        def update_tag(content)
          old_declaration =
            if private_registry_url
              "#{private_registry_url}/"
            else
              ""
            end
          old_declaration += "#{dependency.name}:#{dependency.previous_version}"
          escaped_declaration = Regexp.escape(old_declaration)

          old_declaration_regex = /^#{FROM_REGEX}\s+#{escaped_declaration}/

          content.gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(
              ":#{dependency.previous_version}",
              ":#{dependency.version}"
            )
          end
        end

        def dockerfile
          @dockerfile ||= dependency_files.find { |f| f.name == "Dockerfile" }
        end

        def specified_with_digest?
          dependency.requirements.first.fetch(:source).fetch(:type) == "digest"
        end

        def new_digest
          return unless specified_with_digest?
          dependency.requirements.first.fetch(:source).fetch(:digest)
        end

        def old_digest
          return unless specified_with_digest?
          dependency.previous_requirements.first.fetch(:source).fetch(:digest)
        end

        def private_registry_url
          dependency.requirements.first[:source][:registry]
        end
      end
    end
  end
end
