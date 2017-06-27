# frozen_string_literal: true
require "gems"
require "gemnasium/parser"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module BundlerDefinitionVersionPatch
  def index
    @index ||= super.tap do |index|
      if ruby_version
        requested_version = ruby_version.to_gem_version_with_patchlevel
        index << Gem::Specification.new("ruby\0", requested_version)
      end
    end
  end
end
Bundler::Definition.prepend(BundlerDefinitionVersionPatch)

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        GIT_COMMAND_ERROR_REGEX = /`(?<command>.*)`/

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        private

        def fetch_latest_version
          source =
            SharedHelpers.in_a_temporary_directory do |dir|
              write_temporary_dependency_files_to(dir)

              SharedHelpers.in_a_forked_process do
                definition = ::Bundler::Definition.build(
                  File.join(dir, "Gemfile"),
                  File.join(dir, "Gemfile.lock"),
                  gems: [dependency.name]
                )

                definition.dependencies.
                  find { |dep| dep.name == dependency.name }.source
              end
            end

          case source
          when NilClass then latest_rubygems_version
          when ::Bundler::Source::Rubygems then latest_private_version(source)
          end
        rescue SharedHelpers::ChildProcessFailed => error
          handle_bundler_errors(error)
        end

        def fetch_latest_resolvable_version
          SharedHelpers.in_a_temporary_directory do |dir|
            write_temporary_dependency_files_to(dir)

            SharedHelpers.in_a_forked_process do
              definition = ::Bundler::Definition.build(
                File.join(dir, "Gemfile"),
                File.join(dir, "Gemfile.lock"),
                gems: [dependency.name]
              )

              dependency_source = definition.dependencies.
                                  find { |d| d.name == dependency.name }.source

              # We don't want to bump gems with a git source, so exit early
              next nil if dependency_source.is_a?(::Bundler::Source::Git)

              definition.resolve_remotely!
              definition.resolve.
                find { |dep| dep.name == dependency.name }.version
            end
          end
        rescue SharedHelpers::ChildProcessFailed => error
          handle_bundler_errors(error)
        end

        def handle_bundler_errors(error)
          case error.error_class
          when "Bundler::Dsl::DSLError"
            # We couldn't evaluate the Gemfile, let alone resolve it
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotEvaluatable, msg
          when "Bundler::VersionConflict", "Bundler::GemNotFound"
            # We successfully evaluated the Gemfile, but couldn't resolve it
            # (e.g., because a gem couldn't be found in any of the specified
            # sources, or because it specified conflicting versions)
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotResolvable, msg
          when "Bundler::Source::Git::GitCommandError"
            # A git command failed. This is usually because we don't have access
            # to the specified repo, and gets a special error so it can be
            # handled separately
            command = error.message.match(GIT_COMMAND_ERROR_REGEX)[:command]
            raise Dependabot::GitCommandError, command
          when "Bundler::PathError"
            # A dependency was specified using a path which we don't have access
            # to (and therefore can't resolve)
            raise if path_based_dependencies.none?
            raise Dependabot::PathBasedDependencies,
                  path_based_dependencies.map(&:name)
          else
            raise
          end
        end

        def latest_rubygems_version
          # Note: Rubygems excludes pre-releases from the `Gems.info` response,
          # so no need to filter them out.
          return nil if Gems.info(dependency.name)["version"].nil?
          Gem::Version.new(Gems.info(dependency.name)["version"])
        end

        def latest_private_version(dependency_source)
          gem_fetchers =
            dependency_source.fetchers.flat_map(&:fetchers).
            select { |f| f.is_a?(::Bundler::Fetcher::Dependency) }

          versions =
            gem_fetchers.
            flat_map { |f| f.unmarshalled_dep_gems([dependency.name]) }.
            map { |details| Gem::Version.new(details.fetch(:number)) }

          versions.reject(&:prerelease?).sort.last
        end

        def gemfile
          gemfile = dependency_files.find { |f| f.name == "Gemfile" }
          raise "No Gemfile!" unless gemfile
          gemfile
        end

        def lockfile
          lockfile = dependency_files.find { |f| f.name == "Gemfile.lock" }
          raise "No Gemfile.lock!" unless lockfile
          lockfile
        end

        def path_based_dependencies
          ::Bundler::LockfileParser.new(lockfile.content).specs.select do |spec|
            spec.source.is_a?(::Bundler::Source::Path)
          end
        end

        def write_temporary_dependency_files_to(dir)
          File.write(
            File.join(dir, "Gemfile"),
            gemfile_for_update_check
          )
          File.write(
            File.join(dir, "Gemfile.lock"),
            lockfile_for_update_check
          )
        end

        def gemfile_for_update_check
          gemfile_content = gemfile.content
          gemfile_content = remove_dependency_requirement(gemfile_content)
          prepend_git_auth_details(gemfile_content)
        end

        def lockfile_for_update_check
          lockfile_content = lockfile.content
          prepend_git_auth_details(lockfile_content)
        end

        # Replace the original gem requirements with a ">=" requirement to
        # unlock the gem during version checking
        def remove_dependency_requirement(gemfile_content)
          gemfile_content.
            to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
            find { Regexp.last_match[:name] == dependency.name }

          original_gem_declaration_string = Regexp.last_match.to_s
          updated_gem_declaration_string =
            original_gem_declaration_string.
            sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_req|
              matcher_regexp = /(=|!=|>=|<=|~>|>|<)[ \t]*/
              if old_req.match?(matcher_regexp)
                old_req.sub(matcher_regexp, ">= ")
              else
                old_req.sub(Gemnasium::Parser::Patterns::VERSION) do |old_v|
                  ">= #{old_v}"
                end
              end
            end

          gemfile_content.gsub(
            original_gem_declaration_string,
            updated_gem_declaration_string
          )
        end

        def prepend_git_auth_details(gemfile_content)
          gemfile_content.gsub(
            "git@github.com:",
            "https://x-access-token:#{github_access_token}@github.com/"
          )
        end
      end
    end
  end
end
