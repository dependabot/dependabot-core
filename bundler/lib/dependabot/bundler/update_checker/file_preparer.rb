# typed: true
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/cached_lockfile_parser"
require "dependabot/bundler/file_updater/gemspec_sanitizer"
require "dependabot/bundler/file_updater/git_pin_replacer"
require "dependabot/bundler/file_updater/git_source_remover"
require "dependabot/bundler/file_updater/requirement_replacer"
require "dependabot/bundler/file_updater/gemspec_dependency_name_finder"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/file_updater/ruby_requirement_setter"

module Dependabot
  module Bundler
    class UpdateChecker
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

        # Can't be a constant because some of these don't exist in bundler
        # 1.15, which Heroku uses, which causes an exception on boot.
        def gemspec_sources
          [
            ::Bundler::Source::Path,
            ::Bundler::Source::Gemspec
          ]
        end

        def initialize(dependency_files:, dependency:,
                       remove_git_source: false,
                       unlock_requirement: true,
                       replacement_git_pin: nil,
                       latest_allowable_version: nil,
                       lock_ruby_version: true)
          @dependency_files         = dependency_files
          @dependency               = dependency
          @remove_git_source        = remove_git_source
          @unlock_requirement       = unlock_requirement
          @replacement_git_pin      = replacement_git_pin
          @latest_allowable_version = latest_allowable_version
          @lock_ruby_version        = lock_ruby_version
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
              directory: file.directory,
              support_file: file.support_file?
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
          files += [
            lockfile,
            ruby_version_file,
            tool_versions_file,
            *imported_ruby_files,
            *specification_files
          ].compact
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        private

        attr_reader :dependency_files
        attr_reader :dependency
        attr_reader :replacement_git_pin
        attr_reader :latest_allowable_version

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
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

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

        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        def specification_files
          dependency_files.select { |f| f.name.end_with?(".specification") }
        end

        def top_level_gemspecs
          dependency_files
            .select { |f| f.name.end_with?(".gemspec") }
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def tool_versions_file
          dependency_files.find { |f| f.name == ".tool-versions" }
        end

        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - top_level_gemspecs
        end

        def imported_ruby_files
          dependency_files
            .select { |f| f.name.end_with?(".rb") }
            .reject { |f| f.name == "gems.rb" }
        end

        def gemfile_content_for_update_check(file)
          content = file.content
          content = replace_gemfile_constraint(content, file.name)
          content = remove_git_source(content) if remove_git_source?
          content = replace_git_pin(content) if replace_git_pin?
          content = lock_ruby_version(content) if lock_ruby_version?(file)
          content
        end

        def gemspec_content_for_update_check(gemspec)
          content = gemspec.content
          content = replace_gemspec_constraint(content, gemspec.name)
          sanitize_gemspec_content(content)
        end

        def replace_gemfile_constraint(content, filename)
          FileUpdater::RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemfile,
            updated_requirement: updated_version_requirement_string(filename),
            insert_if_bare: true
          ).rewrite(content)
        end

        def replace_gemspec_constraint(content, filename)
          FileUpdater::RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemspec,
            updated_requirement: updated_version_requirement_string(filename),
            insert_if_bare: true
          ).rewrite(content)
        end

        def sanitize_gemspec_content(gemspec_content)
          new_version = replacement_version_for_gemspec(gemspec_content)

          FileUpdater::GemspecSanitizer
            .new(replacement_version: new_version)
            .rewrite(gemspec_content)
        end

        def updated_version_requirement_string(filename)
          lower_bound_req = updated_version_req_lower_bound(filename)

          return lower_bound_req if latest_allowable_version.nil?
          return lower_bound_req unless Gem::Version.correct?(latest_allowable_version)

          lower_bound_req + ", <= #{latest_allowable_version}"
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def updated_version_req_lower_bound(filename)
          original_req = dependency.requirements
                                   .find { |r| r.fetch(:file) == filename }
                                   &.fetch(:requirement)

          if original_req && !unlock_requirement? then original_req
          elsif dependency.version&.match?(/^[0-9a-f]{40}$/) then ">= 0"
          elsif dependency.version then ">= #{dependency.version}"
          else
            version_for_requirement =
              dependency.requirements.map { |r| r[:requirement] }
                        .reject { |req_string| req_string.start_with?("<") }
                        .select { |req_string| req_string.match?(VERSION_REGEX) }
                        .map { |req_string| req_string.match(VERSION_REGEX) }
                        .select { |version| Gem::Version.correct?(version) }
                        .max_by { |version| Gem::Version.new(version) }

            ">= #{version_for_requirement || 0}"
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def remove_git_source(content)
          FileUpdater::GitSourceRemover.new(
            dependency: dependency
          ).rewrite(content)
        end

        def replace_git_pin(content)
          FileUpdater::GitPinReplacer.new(
            dependency: dependency,
            new_pin: replacement_git_pin
          ).rewrite(content)
        end

        def lock_ruby_version(gemfile_content)
          top_level_gemspecs.each do |gs|
            gemfile_content = FileUpdater::RubyRequirementSetter
                              .new(gemspec: gs).rewrite(gemfile_content)
          end

          gemfile_content
        end

        def lock_ruby_version?(file)
          @lock_ruby_version && file == gemfile
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def replacement_version_for_gemspec(gemspec_content)
          return "0.0.1" unless lockfile

          gemspec_specs =
            CachedLockfileParser.parse(sanitized_lockfile_content).specs
                                .select { |s| gemspec_sources.include?(s.source.class) }

          gem_name =
            FileUpdater::GemspecDependencyNameFinder
            .new(gemspec_content: gemspec_content)
            .dependency_name

          return gemspec_specs.first&.version || "0.0.1" unless gem_name

          spec = gemspec_specs.find { |s| s.name == gem_name }
          spec&.version || gemspec_specs.first&.version || "0.0.1"
        end
        # rubocop:enable Metrics/PerceivedComplexity

        # TODO: Stop sanitizing the lockfile once we have bundler 2 installed
        def sanitized_lockfile_content
          re = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
          lockfile.content.gsub(re, "")
        end
      end
    end
  end
end
