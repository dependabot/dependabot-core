# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
        require_relative "bundler/gemfile_updater"
        require_relative "bundler/gemspec_updater"
        require_relative "bundler/lockfile_updater"

        def self.updated_files_regex
          [/^Gemfile$/, /^Gemfile\.lock$/, %r{^[^/]*\.gemspec$}]
        end

        def updated_dependency_files
          updated_files = []

          if gemfile && file_changed?(gemfile)
            updated_files <<
              updated_file(
                file: gemfile,
                content: updated_gemfile_content(gemfile)
              )
          end

          if lockfile && dependencies.any?(&:appears_in_lockfile?)
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          top_level_gemspecs.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(file: file, content: updated_gemspec_content(file))
          end

          evaled_gemfiles.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(file: file, content: updated_gemfile_content(file))
          end

          updated_files
        end

        private

        def check_required_files
          file_names = dependency_files.map(&:name)

          if file_names.include?("Gemfile.lock") &&
             !file_names.include?("Gemfile")
            raise "A Gemfile must be provided if a lockfile is!"
          end

          return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
          return if file_names.include?("Gemfile")

          raise "A gemspec or Gemfile must be provided!"
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def evaled_gemfiles
          @evaled_gemfiles ||=
            dependency_files.
            reject { |f| f.name.end_with?(".gemspec") }.
            reject { |f| f.name.end_with?(".lock") }.
            reject { |f| f.name.end_with?(".ruby-version") }.
            reject { |f| f.name == "Gemfile" }
        end

        def updated_gemfile_content(file)
          GemfileUpdater.new(
            dependencies: dependencies,
            gemfile: file
          ).updated_gemfile_content
        end

        def updated_gemspec_content(gemspec)
          GemspecUpdater.new(
            dependencies: dependencies,
            gemspec: gemspec
          ).updated_gemspec_content
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            LockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              credentials: credentials
            ).updated_lockfile_content
        end

        def top_level_gemspecs
          dependency_files.select { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
        end
      end
    end
  end
end
