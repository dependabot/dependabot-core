# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex < Base
        def self.updated_files_regex
          [
            /^mix\.exs$/,
            /^mix\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if file_changed?(mixfile)
            updated_files <<
              updated_file(file: mixfile, content: updated_mixfile_content)
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          updated_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency for Elixir
          dependencies.first
        end

        def check_required_files
          raise "No mix.exs!" unless get_original_file("mix.exs")
        end

        def mixfile
          @mixfile ||= get_original_file("mix.exs")
        end

        def lockfile
          @lockfile ||= get_original_file("mix.lock")
        end

        def updated_lockfile_content
          # TODO: Write this!
          lockfile.content
        end

        def updated_mixfile_content
          file = mixfile

          dependencies.
            select { |dep| requirement_changed?(file, dep) }.
            reduce(file.content.dup) do |content, dep|
              updated_requirement =
                dep.requirements.find { |r| r[:file] == file.name }.
                fetch(:requirement)

              old_req =
                dep.previous_requirements.find { |r| r[:file] == file.name }.
                fetch(:requirement)

              declaration_regex =
                /:#{Regexp.escape(dep.name)}.*#{Regexp.escape(old_req)}/
              updated_content = content.gsub(declaration_regex) do |declaration|
                declaration.gsub(old_req, updated_requirement)
              end

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end
      end
    end
  end
end
