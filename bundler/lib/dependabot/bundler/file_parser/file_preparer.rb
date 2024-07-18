# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/file_parsers/base"
require "dependabot/bundler/file_updater/gemspec_sanitizer"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      class FilePreparer
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def prepared_dependency_files
          files = gemspecs.compact.map do |file|
            DependencyFile.new(
              name: file.name,
              content: sanitize_gemspec_content(T.must(file.content)),
              directory: file.directory,
              support_file: file.support_file?
            )
          end

          files + [
            gemfile,
            *evaled_gemfiles,
            lockfile,
            ruby_version_file,
            tool_versions_file,
            *imported_ruby_files,
            *specification_files
          ].compact
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def evaled_gemfiles
          dependency_files
            .reject { |f| f.name.end_with?(".gemspec") }
            .reject { |f| f.name.end_with?(".specification") }
            .reject { |f| f.name.end_with?(".lock") }
            .reject { |f| f.name == "Gemfile" }
            .reject { |f| f.name == "gems.rb" }
            .reject { |f| f.name == "gems.locked" }
            .reject(&:support_file?)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def specification_files
          dependency_files.select { |f| f.name.end_with?(".specification") }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def gemspecs
          dependency_files.select { |f| f.name.end_with?(".gemspec") }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def tool_versions_file
          dependency_files.find { |f| f.name == ".tool-versions" }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def imported_ruby_files
          dependency_files
            .select { |f| f.name.end_with?(".rb") }
            .reject { |f| f.name == "gems.rb" }
        end

        sig { params(gemspec_content: String).returns(String) }
        def sanitize_gemspec_content(gemspec_content)
          # No need to set the version correctly - this is just an update
          # check so we're not going to persist any changes to the lockfile.
          FileUpdater::GemspecSanitizer
            .new(replacement_version: "0.0.1")
            .rewrite(gemspec_content)
        end
      end
    end
  end
end
