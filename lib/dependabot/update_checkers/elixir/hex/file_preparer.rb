# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/update_checkers/elixir/hex"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex
        # This class takes a set of dependency files and sanitizes them for use
        # in UpdateCheckers::Elixir::Hex.
        class FilePreparer
          def initialize(dependency_files:, dependency:,
                         unlock_requirement: true,
                         replacement_git_pin: nil)
            @dependency_files = dependency_files
            @dependency = dependency
            @unlock_requirement = unlock_requirement
            @replacement_git_pin = replacement_git_pin
          end

          def prepared_dependency_files
            files = []
            files += mixfiles.map do |file|
              DependencyFile.new(
                name: file.name,
                content: mixfile_content_for_update_check(file),
                directory: file.directory
              )
            end
            files << lockfile
            files
          end

          private

          attr_reader :dependency_files, :dependency, :replacement_git_pin

          def unlock_requirement?
            @unlock_requirement
          end

          def replace_git_pin?
            !replacement_git_pin.nil?
          end

          def mixfile_content_for_update_check(file)
            content = file.content

            unless dependency_appears_in_file?(file.name)
              return sanitize_mixfile(content)
            end

            if unlock_requirement?
              content = relax_version(content, filename: file.name)
            end
            if replace_git_pin?
              content = replace_git_pin(content, filename: file.name)
            end

            sanitize_mixfile(content)
          end

          def relax_version(content, filename:)
            old_requirement =
              dependency.requirements.find { |r| r.fetch(:file) == filename }.
              fetch(:requirement)

            return content unless old_requirement

            new_requirement =
              if dependency.version
                ">= #{dependency.version}"
              elsif wants_prerelease?
                ">= 0.0.1-rc1"
              else
                ">= 0"
              end

            requirement_line_regex =
              /
                :#{Regexp.escape(dependency.name)},.*
                #{Regexp.escape(old_requirement)}
              /x

            content.gsub(requirement_line_regex) do |requirement_line|
              requirement_line.gsub(old_requirement, new_requirement)
            end
          end

          def replace_git_pin(content, filename:)
            old_pin =
              dependency.requirements.find { |r| r.fetch(:file) == filename }&.
              dig(:source, :ref)

            return content unless old_pin

            requirement_line_regex =
              /
                :#{Regexp.escape(dependency.name)},.*
                (?:ref|tag):\s+["']#{Regexp.escape(old_pin)}["']
              /x

            content.gsub(requirement_line_regex) do |requirement_line|
              requirement_line.gsub(old_pin, replacement_git_pin)
            end
          end

          def sanitize_mixfile(content)
            content.
              gsub(/File\.read!\(.*?\)/, '"0.0.1"').
              gsub(/File\.read\(.*?\)/, '{:ok, "0.0.1"}')
          end

          def mixfiles
            mixfiles =
              dependency_files.
              select { |f| f.name.end_with?("mix.exs") }
            raise "No mix.exs!" unless mixfiles.any?
            mixfiles
          end

          def lockfile
            lockfile = dependency_files.find { |f| f.name == "mix.lock" }
            raise "No mix.lock!" unless lockfile
            lockfile
          end

          def wants_prerelease?
            current_version = dependency.version
            if current_version &&
               version_class.correct?(current_version) &&
               version_class.new(current_version).prerelease?
              return true
            end

            dependency.requirements.any? do |req|
              req[:requirement].match?(/\d-[A-Za-z0-9]/)
            end
          end

          def version_class
            Hex::Version
          end

          def dependency_appears_in_file?(file_name)
            dependency.requirements.any? { |r| r[:file] == file_name }
          end
        end
      end
    end
  end
end
