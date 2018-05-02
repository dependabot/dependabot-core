# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler"
require "dependabot/file_updaters/ruby/bundler/gemspec_sanitizer"
require "dependabot/file_updaters/ruby/bundler/git_pin_replacer"
require "dependabot/file_updaters/ruby/bundler/git_source_remover"
require "dependabot/file_updaters/ruby/bundler/requirement_replacer"
require "dependabot/file_updaters/ruby/bundler/gemspec_dependency_name_finder"
require "dependabot/update_checkers/ruby/bundler/ruby_requirement_setter"

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
        #   imperfect - an alternative would be to clone the repo
        # - Sets the ruby version in the Gemfile to be the lowest possible
        #   version allowed by the gemspec, if the gemspec has a required ruby
        #   version range
        class FilePreparer
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

          def initialize(dependency_files:, dependency:,
                         remove_git_source: false,
                         unlock_requirement: true,
                         replacement_git_pin: nil)
            @dependency_files = dependency_files
            @dependency = dependency
            @remove_git_source = remove_git_source
            @unlock_requirement = unlock_requirement
            @replacement_git_pin = replacement_git_pin
          end

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/MethodLength
          def prepared_dependency_files
            files = []

            if gemfile
              files << DependencyFile.new(
                name: gemfile.name,
                content: gemfile_content_for_update_check(gemfile),
                directory: gemfile.directory
              )
            end

            top_level_gemspecs.each do |gemspec|
              files << DependencyFile.new(
                name: gemspec.name,
                content: gemspec_content_for_update_check(gemspec),
                directory: gemspec.directory
              )
            end

            path_gemspecs.each do |file|
              files << DependencyFile.new(
                name: file.name,
                content: sanitize_gemspec_content(file.content),
                directory: file.directory
              )
            end

            evaled_gemfiles.each do |file|
              files << DependencyFile.new(
                name: file.name,
                content: gemfile_content_for_update_check(file),
                directory: file.directory
              )
            end

            # No editing required for lockfile or Ruby version file
            files += [lockfile, ruby_version_file, *imported_ruby_files].compact
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/MethodLength

          private

          attr_reader :dependency_files, :dependency, :replacement_git_pin

          def remove_git_source?
            @remove_git_source
          end

          def unlock_requirement?
            @unlock_requirement
          end

          def replace_git_pin?
            !replacement_git_pin.nil?
          end

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

          def top_level_gemspecs
            dependency_files.select { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
          end

          def ruby_version_file
            dependency_files.find { |f| f.name == ".ruby-version" }
          end

          def path_gemspecs
            all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
            all - top_level_gemspecs
          end

          def imported_ruby_files
            dependency_files.select { |f| f.name.end_with?(".rb") }
          end

          def gemfile_content_for_update_check(file)
            content = file.content
            content = replace_gemfile_constraint(content) if unlock_requirement?
            content = remove_git_source(content) if remove_git_source?
            content = replace_git_pin(content) if replace_git_pin?
            content = update_ruby_version(content) if file == gemfile
            content
          end

          def gemspec_content_for_update_check(gemspec)
            content = gemspec.content
            content = replace_gemspec_constraint(content) if unlock_requirement?
            sanitize_gemspec_content(content)
          end

          def replace_gemfile_constraint(content)
            FileUpdaters::Ruby::Bundler::RequirementReplacer.new(
              dependency: dependency,
              file_type: :gemfile,
              updated_requirement: updated_version_requirement_string
            ).rewrite(content)
          end

          def replace_gemspec_constraint(content)
            FileUpdaters::Ruby::Bundler::RequirementReplacer.new(
              dependency: dependency,
              file_type: :gemspec,
              updated_requirement: updated_version_requirement_string
            ).rewrite(content)
          end

          def sanitize_gemspec_content(gemspec_content)
            new_version = replacement_version_for_gemspec(gemspec_content)

            FileUpdaters::Ruby::Bundler::GemspecSanitizer.
              new(replacement_version: new_version).
              rewrite(gemspec_content)
          end

          def updated_version_requirement_string
            return ">= 0" if dependency.version&.match?(/^[0-9a-f]{40}$/)
            return ">= #{dependency.version}" if dependency.version

            version_for_requirement =
              dependency.requirements.map { |r| r[:requirement] }.
              reject { |req_string| req_string.start_with?("<") }.
              select { |req_string| req_string.match?(VERSION_REGEX) }.
              map { |req_string| req_string.match(VERSION_REGEX) }.
              select { |version| Gem::Version.correct?(version) }.
              max_by { |version| Gem::Version.new(version) }

            ">= #{version_for_requirement || 0}"
          end

          def remove_git_source(content)
            FileUpdaters::Ruby::Bundler::GitSourceRemover.new(
              dependency: dependency
            ).rewrite(content)
          end

          def replace_git_pin(content)
            FileUpdaters::Ruby::Bundler::GitPinReplacer.new(
              dependency: dependency,
              new_pin: replacement_git_pin
            ).rewrite(content)
          end

          def update_ruby_version(gemfile_content)
            top_level_gemspecs.each do |gs|
              gemfile_content =
                RubyRequirementSetter.new(gemspec: gs).rewrite(gemfile_content)
            end

            gemfile_content
          end

          def replacement_version_for_gemspec(gemspec_content)
            return "0.0.1" unless lockfile

            parsed_lockfile = ::Bundler::LockfileParser.new(lockfile.content)
            gem_name =
              FileUpdaters::Ruby::Bundler::GemspecDependencyNameFinder.
              new(gemspec_content: gemspec_content).
              dependency_name

            return "0.0.1" unless gem_name
            spec = parsed_lockfile.specs.find { |s| s.name == gem_name }
            spec&.version || "0.0.1"
          end
        end
      end
    end
  end
end
