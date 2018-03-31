# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler"
require "dependabot/file_updaters/ruby/bundler/gemspec_sanitizer"
require "dependabot/file_updaters/ruby/bundler/git_pin_replacer"
require "dependabot/file_updaters/ruby/bundler/git_source_remover"
require "dependabot/file_updaters/ruby/bundler/requirement_replacer"
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
          REQUIRED_RUBY_VERSION = /required_ruby_version/
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

            if gemspec
              files << DependencyFile.new(
                name: gemspec.name,
                content: gemspec_content_for_update_check,
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
            files += [lockfile, ruby_version_file].compact
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

          def gemfile_content_for_update_check(file)
            content = file.content
            content = replace_gemfile_constraint(content) if unlock_requirement?
            content = remove_git_source(content) if remove_git_source?
            content = replace_git_pin(content) if replace_git_pin?
            content = update_ruby_version(content) if file == gemfile
            content
          end

          def gemspec_content_for_update_check
            content = gemspec.content
            content = replace_gemspec_constraint(content) if unlock_requirement?
            sanitize_gemspec_content(content)
          end

          def replace_gemfile_constraint(content)
            updated_version =
              if dependency.version&.match?(/^[0-9a-f]{40}$/) then 0
              elsif dependency.version then dependency.version
              else 0
              end

            FileUpdaters::Ruby::Bundler::RequirementReplacer.new(
              dependency: dependency,
              file_type: :gemfile,
              updated_requirement: ">= #{updated_version}"
            ).rewrite(content)
          end

          def replace_gemspec_constraint(content)
            FileUpdaters::Ruby::Bundler::RequirementReplacer.new(
              dependency: dependency,
              file_type: :gemspec,
              updated_requirement: ">= 0"
            ).rewrite(content)
          end

          def sanitize_gemspec_content(gemspec_content)
            # No need to set the version correctly - this is just an update
            # check so we're not going to persist any changes to the lockfile.
            FileUpdaters::Ruby::Bundler::GemspecSanitizer.
              new(replacement_version: "0.0.1").
              rewrite(gemspec_content)
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

          def update_ruby_version(content)
            return content unless gemspec
            RubyRequirementSetter.new(gemspec: gemspec).rewrite(content)
          end
        end
      end
    end
  end
end
