# frozen_string_literal: true
require "bundler_definition_version_patch"
require "bundler_metadata_dependencies_patch"
require "excon"
require "gems"
require "gemnasium/parser"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
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
                ::Bundler.instance_variable_set(:@root, Pathname.new(dir))
                ::Bundler.settings["github.com"] =
                  "x-access-token:#{github_access_token}"

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
              ::Bundler.instance_variable_set(:@root, Pathname.new(dir))
              ::Bundler.settings["github.com"] =
                "x-access-token:#{github_access_token}"

              definition = ::Bundler::Definition.build(
                File.join(dir, "Gemfile"),
                File.join(dir, "Gemfile.lock"),
                gems: [dependency.name]
              )

              dependency_source = definition.dependencies.
                                  find { |d| d.name == dependency.name }.source

              # We don't want to bump gems with a path/git source, so exit early
              next nil if dependency_source.is_a?(::Bundler::Source::Path)

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
          when "Bundler::VersionConflict", "Bundler::GemNotFound",
               "Gem::InvalidSpecificationException"
            # We successfully evaluated the Gemfile, but couldn't resolve it
            # (e.g., because a gem couldn't be found in any of the specified
            # sources, or because it specified conflicting versions)
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotResolvable, msg
          when "Bundler::Source::Git::GitCommandError"
            # A git command failed. This is usually because we don't have access
            # to the specified repo.
            #
            # Check if there are any repos we don't have access to, and raise an
            # error with details if so. Otherwise re-raise.
            raise unless inaccessible_git_dependencies.any?
            raise(
              Dependabot::GitDependenciesNotReachable,
              inaccessible_git_dependencies.map { |s| s.source.uri }
            )
          else raise
          end
        end

        def inaccessible_git_dependencies
          ::Bundler::LockfileParser.new(lockfile.content).
            specs.select do |spec|
              next false unless spec.source.is_a?(::Bundler::Source::Git)

              # Piggy-back off some private Bundler methods to configure the
              # URI with auth details in the same way Bundler does.
              git_proxy = spec.source.send(:git_proxy)
              uri = git_proxy.send(:configured_uri_for, spec.source.uri)
              Excon.get(uri).status == 404
            end
        end

        def latest_rubygems_version
          # Note: Rubygems excludes pre-releases from the `Gems.info` response,
          # so no need to filter them out.
          latest_info = Gems.info(dependency.name)

          return nil if latest_info["version"].nil?
          Gem::Version.new(latest_info["version"])
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
            spec.source.instance_of?(::Bundler::Source::Path)
          end
        end

        def write_temporary_dependency_files_to(dir)
          File.write(
            File.join(dir, "Gemfile"),
            gemfile_for_update_check
          )
          File.write(
            File.join(dir, "Gemfile.lock"),
            lockfile.content
          )
          gemspecs.each do |gemspec|
            path = File.join(dir, gemspec.name)
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, gemspec.content)
          end
        end

        def gemspecs
          dependency_files.select { |f| f.name.end_with?(".gemspec") }
        end

        def gemfile_for_update_check
          remove_dependency_requirement(gemfile.content)
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
      end
    end
  end
end
