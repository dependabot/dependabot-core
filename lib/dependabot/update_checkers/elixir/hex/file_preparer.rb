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
                         unlock_requirement: true)
            @dependency_files = dependency_files
            @dependency = dependency
            @unlock_requirement = unlock_requirement
          end

          def prepared_dependency_files
            files = []
            files += mixfiles.map do |file|
              DependencyFile.new(
                name: file.name,
                content: prepare_mixfile(file),
                directory: file.directory
              )
            end
            files << lockfile
            files
          end

          private

          attr_reader :dependency_files, :dependency

          def unlock_requirement?
            @unlock_requirement
          end

          def prepare_mixfile(file)
            content = file.content
            if unlock_requirement? && dependency_appears_in_file?(file.name)
              content = relax_version(content, filename: file.name)
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

          def dependency_appears_in_file?(file_name)
            dependency.requirements.any? { |r| r[:file] == file_name }
          end
        end
      end
    end
  end
end
