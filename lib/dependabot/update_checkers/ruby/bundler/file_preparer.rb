# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/file_updaters/ruby/bundler"
require "dependabot/dependency_file"
require "gemnasium/parser"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        # This class takes a set of dependency files and sanitizes them for use
        # in UpdateCheckers::Ruby::Bundler. In particular, it:
        # - Removes any version requirement on the dependency being updated
        #   (in the Gemfile)
        # - Sanitizes any provided gemspecs to remove file imports etc. (since
        #   Dependabot doesn't pull down the entire repo). This process is
        #   imperfect - an alternative would be to cloen the repo
        class FilePreparer
          def initialize(dependency_files:, dependency:)
            @dependency_files = dependency_files
            @dependency = dependency
          end

          def prepared_dependency_files
            files = []

            if gemfile
              files << DependencyFile.new(
                name: gemfile.name,
                content: gemfile_content_for_update_check,
                directory: gemfile.directory
              )
            end

            if gemspec
              files << DependencyFile.new(
                name: gemspec.name,
                content: gemspec_content_for_update_check,
                directory: gemspec.directory
              )
            end

            path_gemspecs.compact.each do |file|
              files << DependencyFile.new(
                name: file.name,
                content: sanitized_gemspec_content(file.content),
                directory: file.directory
              )
            end

            # No editing required for lockfile or Ruby version file
            files += [lockfile, ruby_version_file].compact
          end

          private

          attr_reader :dependency_files, :dependency

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end

          def gemspec
            dependency_files.find { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
          end

          def ruby_version_file
            dependency_files.find { |f| f.name == ".ruby-version" }
          end

          def path_gemspecs
            all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
            all - [gemspec]
          end

          def gemfile_content_for_update_check
            content = update_gemfile_requirement(gemfile.content)
            content
          end

          def gemspec_content_for_update_check
            content =
              if original_gemspec_declaration_string
                gemspec.content.gsub(
                  original_gemspec_declaration_string,
                  updated_gemspec_declaration_string
                )
              else
                gemspec.content
              end

            sanitized_gemspec_content(content)
          end

          def original_gemspec_declaration_string
            matches = []
            regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX

            @original_gemspec_declaration_string ||=
              begin
                gemspec.content.scan(regex) { matches << Regexp.last_match }
                matches.find { |match| match[:name] == dependency.name }&.to_s
              end
          end

          def updated_gemspec_declaration_string
            regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX
            original_requirement =
              regex.match(original_gemspec_declaration_string)[:requirements]

            original_gemspec_declaration_string.
              sub(original_requirement, '">= 0"')
          end

          def sanitized_gemspec_content(gemspec_content)
            # No need to set the version correctly - this is just an update
            # check so we're not going to persist any changes to the lockfile.
            gemspec_content.
              gsub(/^\s*require.*$/, "").
              gsub(/=.*VERSION.*$/, "= '0.0.1'")
          end

          # Replace the original gem requirements with a ">=" requirement to
          # unlock the gem during version checking
          def update_gemfile_requirement(gemfile_content)
            unless gemfile_content.
                   to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
                   find { Regexp.last_match[:name] == dependency.name }
              return gemfile_content
            end

            replacement_version =
              if dependency.version&.match?(/^[0-9a-f]{40}$/) then 0
              else dependency.version || 0
              end

            original_gem_declaration_string = Regexp.last_match.to_s
            updated_gem_declaration_string =
              original_gem_declaration_string.
              sub(
                Gemnasium::Parser::Patterns::REQUIREMENTS,
                "'>= #{replacement_version}'"
              )

            gemfile_content.gsub(
              original_gem_declaration_string,
              updated_gem_declaration_string
            )
          end
        end
      end
    end
  end
end
