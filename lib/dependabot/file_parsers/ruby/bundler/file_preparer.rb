# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/file_parsers/ruby/bundler"
require "dependabot/file_updaters/ruby/bundler/gemspec_sanitizer"

module Dependabot
  module FileParsers
    module Ruby
      class Bundler
        class FilePreparer
          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def prepared_dependency_files
            files = []

            gemspecs.compact.each do |file|
              files << DependencyFile.new(
                name: file.name,
                content: sanitize_gemspec_content(file.content),
                directory: file.directory
              )
            end

            files +=
              [gemfile, *evaled_gemfiles, lockfile, ruby_version_file].compact
          end

          private

          attr_reader :dependency_files

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def evaled_gemfiles
            dependency_files.
              reject { |f| f.name.end_with?(".gemspec") }.
              reject { |f| f.name.end_with?(".lock") }.
              reject { |f| f.name.end_with?(".ruby-version") }.
              reject { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end

          def gemspecs
            dependency_files.select { |f| f.name.end_with?(".gemspec") }
          end

          def ruby_version_file
            dependency_files.find { |f| f.name == ".ruby-version" }
          end

          def sanitize_gemspec_content(gemspec_content)
            # No need to set the version correctly - this is just an update
            # check so we're not going to persist any changes to the lockfile.
            FileUpdaters::Ruby::Bundler::GemspecSanitizer.
              new(replacement_version: "0.0.1").
              rewrite(gemspec_content)
          end
        end
      end
    end
  end
end
