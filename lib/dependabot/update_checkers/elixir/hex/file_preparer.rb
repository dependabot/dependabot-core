# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/update_checkers/elixir/hex"
require "dependabot/utils/elixir/version"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex
        # This class takes a set of dependency files and sanitizes them for use
        # in UpdateCheckers::Elixir::Hex.
        class FilePreparer
          def initialize(dependency_files:, dependency:,
                         unlock_requirement: true,
                         replacement_git_pin: nil,
                         latest_allowable_version: nil)
            @dependency_files = dependency_files
            @dependency = dependency
            @unlock_requirement = unlock_requirement
            @replacement_git_pin = replacement_git_pin
            @latest_allowable_version = latest_allowable_version
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

          attr_reader :dependency_files, :dependency, :replacement_git_pin,
                      :latest_allowable_version

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

            content = relax_version(content, filename: file.name)
            if replace_git_pin?
              content = replace_git_pin(content, filename: file.name)
            end

            sanitize_mixfile(content)
          end

          def relax_version(content, filename:)
            old_requirement =
              dependency.requirements.find { |r| r.fetch(:file) == filename }.
              fetch(:requirement)

            new_requirement = updated_version_requirement_string(filename)

            requirement_line_regex =
              if old_requirement
                /
                  :#{Regexp.escape(dependency.name)},.*
                  #{Regexp.escape(old_requirement)}
                /x
              else
                /:#{Regexp.escape(dependency.name)}(,|\s|\})/
              end

            content.gsub(requirement_line_regex) do |requirement_line|
              if old_requirement
                requirement_line.gsub(old_requirement, new_requirement)
              else
                requirement_line.gsub(
                  ":#{dependency.name}",
                  ":#{dependency.name}, \"#{new_requirement}\""
                )
              end
            end
          end

          def updated_version_requirement_string(filename)
            lower_bound_req = updated_version_req_lower_bound(filename)

            return lower_bound_req if latest_allowable_version.nil?
            unless version_class.correct?(latest_allowable_version)
              return lower_bound_req
            end

            lower_bound_req + " and <= #{latest_allowable_version}"
          end

          # rubocop:disable Metrics/AbcSize
          def updated_version_req_lower_bound(filename)
            original_req = dependency.requirements.
                           find { |r| r.fetch(:file) == filename }&.
                           fetch(:requirement)

            if original_req && !unlock_requirement? then original_req
            elsif dependency.version&.match?(/^[0-9a-f]{40}$/) then ">= 0"
            elsif dependency.version then ">= #{dependency.version}"
            else
              version_for_requirement =
                dependency.requirements.map { |r| r[:requirement] }.
                reject { |req_string| req_string.start_with?("<") }.
                select { |req_string| req_string.match?(version_regex) }.
                map { |req_string| req_string.match(version_regex) }.
                select { |version| version_class.correct?(version.to_s) }.
                max_by { |version| version_class.new(version.to_s) }

              ">= #{version_for_requirement || 0}"
            end
          end
          # rubocop:enable Metrics/AbcSize

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
            Utils::Elixir::Version
          end

          def version_regex
            version_class::VERSION_PATTERN
          end

          def dependency_appears_in_file?(file_name)
            dependency.requirements.any? { |r| r[:file] == file_name }
          end
        end
      end
    end
  end
end
