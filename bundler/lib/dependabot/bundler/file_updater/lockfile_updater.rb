# frozen_string_literal: true

require "bundler"

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/bundler/file_updater"
require "dependabot/git_commit_checker"
module Dependabot
  module Bundler
    class FileUpdater
      # rubocop:disable Metrics/ClassLength
      class LockfileUpdater
        require_relative "gemfile_updater"
        require_relative "gemspec_updater"
        require_relative "gemspec_sanitizer"
        require_relative "gemspec_dependency_name_finder"
        require_relative "ruby_requirement_setter"

        LOCKFILE_ENDING =
          /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m.freeze
        GIT_DEPENDENCIES_SECTION = /GIT\n.*?\n\n(?!GIT)/m.freeze
        GIT_DEPENDENCY_DETAILS = /GIT\n.*?\n\n/m.freeze
        GEM_NOT_FOUND_ERROR_REGEX =
          /
            locked\sto\s(?<name>[^\s]+)\s\(|
            not\sfind\s(?<name>[^\s]+)-\d|
            has\s(?<name>[^\s]+)\slocked\sat
          /x.freeze
        RETRYABLE_ERRORS = [::Bundler::HTTPError].freeze

        # Can't be a constant because some of these don't exist in bundler
        # 1.15, which Heroku uses, which causes an exception on boot.
        def gemspec_sources
          [
            ::Bundler::Source::Path,
            ::Bundler::Source::Gemspec
          ]
        end

        def initialize(dependencies:, dependency_files:,
                       repo_contents_path: nil, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              updated_content = build_updated_lockfile

              if lockfile.content == updated_content
                raise "Expected content to change!"
              end

              updated_content
            end
        end

        private

        attr_reader :dependencies, :dependency_files, :repo_contents_path,
                    :credentials

        def build_updated_lockfile
          base_dir = dependency_files.first.directory
          lockfile_body =
            SharedHelpers.in_a_temporary_repo_directory(
              base_dir,
              repo_contents_path
            ) do |tmp_dir|
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                # Set the path for path gemspec correctly
                ::Bundler.instance_variable_set(:@root, tmp_dir)

                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all =
                  ::Gem::Specification.send(:default_stubs, "*.gemspec")

                # Set flags and credentials
                set_bundler_flags_and_credentials

                generate_lockfile
              end
            end
          post_process_lockfile(lockfile_body)
        rescue SharedHelpers::ChildProcessFailed => e
          raise unless ruby_lock_error?(e)

          @dont_lock_ruby_version = true
          retry
        end

        def ruby_lock_error?(error)
          return false unless error.error_class == "Bundler::VersionConflict"
          return false unless error.message.include?(" for gem \"ruby\0\"")
          return false if @dont_lock_ruby_version

          dependency_files.any? { |f| f.name.end_with?(".gemspec") }
        end

        def write_temporary_dependency_files
          File.write(gemfile.name, prepared_gemfile_content(gemfile))
          File.write(lockfile.name, sanitized_lockfile_body)

          top_level_gemspecs.each do |gemspec|
            path = gemspec.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            updated_content = updated_gemspec_content(gemspec)
            File.write(path, sanitized_gemspec_content(updated_content))
          end

          write_ruby_version_file
          write_path_gemspecs
          write_imported_ruby_files

          evaled_gemfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_gemfile_content(file))
          end
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def generate_lockfile
          dependencies_to_unlock = dependencies.map(&:name)

          begin
            definition = build_definition(dependencies_to_unlock)

            old_reqs = lock_deps_being_updated_to_exact_versions(definition)

            definition.resolve_remotely!

            old_reqs.each do |dep_name, old_req|
              d_dep = definition.dependencies.find { |d| d.name == dep_name }
              if old_req == :none then definition.dependencies.delete(d_dep)
              else d_dep.instance_variable_set(:@requirement, old_req)
              end
            end

            cache_vendored_gems(definition) if ::Bundler.app_cache.exist?

            definition.to_lock
          rescue ::Bundler::GemNotFound => e
            unlock_yanked_gem(dependencies_to_unlock, e) && retry
          rescue ::Bundler::VersionConflict => e
            unlock_blocking_subdeps(dependencies_to_unlock, e) && retry
          rescue *RETRYABLE_ERRORS
            raise if @retrying

            @retrying = true
            sleep(rand(1.0..5.0))
            retry
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def cache_vendored_gems(definition)
          # Dependencies that have been unlocked for the update (including
          # sub-dependencies)
          unlocked_gems = definition.instance_variable_get(:@unlock).
                          fetch(:gems)
          bundler_opts = {
            cache_all_platforms: true,
            no_prune: true
          }

          ::Bundler.settings.temporary(**bundler_opts) do
            # Fetch and cache gems on all platforms without pruning
            ::Bundler::Runtime.new(nil, definition).cache

            # Only prune unlocked gems (the original implementation is in
            # Bundler::Runtime)
            cache_path = ::Bundler.app_cache
            resolve = definition.resolve
            prune_gem_cache(resolve, cache_path, unlocked_gems)
            prune_git_and_path_cache(resolve, cache_path)
          end
        end

        # Copied from Bundler::Runtime: Modified to only prune gems that have
        # been unlocked
        def prune_gem_cache(resolve, cache_path, unlocked_gems)
          cached_gems = Dir["#{cache_path}/*.gem"]

          outdated_gems = cached_gems.reject do |path|
            spec = ::Bundler.rubygems.spec_from_gem path

            !unlocked_gems.include?(spec.name) || resolve.any? do |s|
              s.name == spec.name && s.version == spec.version &&
                !s.source.is_a?(::Bundler::Source::Git)
            end
          end

          return unless outdated_gems.any?

          puts "Removing outdated .gem files from #{cache_path}"

          outdated_gems.each do |path|
            puts "  * #{File.basename(path)}"
            File.delete(path)
          end
        end

        # Copied from Bundler::Runtime
        def prune_git_and_path_cache(resolve, cache_path)
          cached_git_and_path = Dir["#{cache_path}/*/.bundlecache"]

          outdated_git_and_path = cached_git_and_path.reject do |path|
            name = File.basename(File.dirname(path))

            resolve.any? do |s|
              s.source.respond_to?(:app_cache_dirname) &&
                s.source.app_cache_dirname == name
            end
          end

          return unless outdated_git_and_path.any?

          puts "Removing outdated git and path gems from #{cache_path}"

          outdated_git_and_path.each do |path|
            path = File.dirname(path)
            puts "  * #{File.basename(path)}"
            FileUtils.rm_rf(path)
          end
        end

        def unlock_yanked_gem(dependencies_to_unlock, error)
          raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)

          gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                     named_captures["name"]
          raise if dependencies_to_unlock.include?(gem_name)

          dependencies_to_unlock << gem_name
        end

        def unlock_blocking_subdeps(dependencies_to_unlock, error)
          all_deps =  ::Bundler::LockfileParser.new(sanitized_lockfile_body).
                      specs.map(&:name).map(&:to_s)
          top_level = build_definition([]).dependencies.
                      map(&:name).map(&:to_s)
          allowed_new_unlocks = all_deps - top_level - dependencies_to_unlock

          raise if allowed_new_unlocks.none?

          # Unlock any sub-dependencies that Bundler reports caused the
          # conflict
          potentials_deps =
            error.cause.conflicts.values.
            flat_map(&:requirement_trees).
            map do |tree|
              tree.find { |req| allowed_new_unlocks.include?(req.name) }
            end.compact.map(&:name)

          # If there are specific dependencies we can unlock, unlock them
          if potentials_deps.any?
            return dependencies_to_unlock.append(*potentials_deps)
          end

          # Fall back to unlocking *all* sub-dependencies. This is required
          # because Bundler's VersionConflict objects don't include enough
          # information to chart the full path through all conflicts unwound
          dependencies_to_unlock.append(*allowed_new_unlocks)
        end

        def build_definition(dependencies_to_unlock)
          defn = ::Bundler::Definition.build(
            gemfile.name,
            lockfile.name,
            gems: dependencies_to_unlock
          )

          # Bundler unlocks the sub-dependencies of gems it is passed even
          # if those sub-deps are top-level dependencies. We only want true
          # subdeps unlocked, like they were in the UpdateChecker, so we
          # mutate the unlocked gems array.
          unlocked = defn.instance_variable_get(:@unlock).fetch(:gems)
          must_not_unlock = defn.dependencies.map(&:name).map(&:to_s) -
                            dependencies_to_unlock
          unlocked.reject! { |n| must_not_unlock.include?(n) }

          defn
        end

        def lock_deps_being_updated_to_exact_versions(definition)
          dependencies.each_with_object({}) do |dep, old_reqs|
            defn_dep = definition.dependencies.find { |d| d.name == dep.name }

            if defn_dep.nil?
              definition.dependencies <<
                ::Bundler::Dependency.new(dep.name, dep.version)
              old_reqs[dep.name] = :none
            elsif git_dependency?(dep) &&
                  defn_dep.source.is_a?(::Bundler::Source::Git)
              defn_dep.source.unlock!
            elsif Gem::Version.correct?(dep.version)
              new_req = Gem::Requirement.create("= #{dep.version}")
              old_reqs[dep.name] = defn_dep.requirement
              defn_dep.instance_variable_set(:@requirement, new_req)
            end
          end
        end

        def write_ruby_version_file
          return unless ruby_version_file

          path = ruby_version_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, ruby_version_file.content)
        end

        def write_path_gemspecs
          path_gemspecs.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file.content))
          end

          specification_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def write_imported_ruby_files
          imported_ruby_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - top_level_gemspecs
        end

        def imported_ruby_files
          dependency_files.
            select { |f| f.name.end_with?(".rb") }.
            reject { |f| f.name == "gems.rb" }
        end

        def top_level_gemspecs
          dependency_files.
            select { |file| file.name.end_with?(".gemspec") }.
            reject(&:support_file?)
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def post_process_lockfile(lockfile_body)
          lockfile_body = reorder_git_dependencies(lockfile_body)
          replace_lockfile_ending(lockfile_body)
        end

        def reorder_git_dependencies(lockfile_body)
          new_section = lockfile_body.match(GIT_DEPENDENCIES_SECTION)&.to_s
          old_section = lockfile.content.match(GIT_DEPENDENCIES_SECTION)&.to_s

          return lockfile_body unless new_section && old_section

          new_deps = new_section.scan(GIT_DEPENDENCY_DETAILS)
          old_deps = old_section.scan(GIT_DEPENDENCY_DETAILS)

          return lockfile_body unless new_deps.count == old_deps.count

          reordered_new_section = new_deps.sort_by do |new_dep_details|
            remote = new_dep_details.match(/remote: (?<remote>.*\n)/)[:remote]
            i = old_deps.index { |details| details.include?(remote) }

            # If this dependency isn't in the old lockfile then we can't rely
            # on that (presumably outdated) lockfile to do reordering.
            # Instead, we just return the default-ordered content just
            # generated.
            return lockfile_body unless i

            i
          end.join

          lockfile_body.gsub(new_section, reordered_new_section)
        end

        def replace_lockfile_ending(lockfile_body)
          # Re-add the old `BUNDLED WITH` version (and remove the RUBY VERSION
          # if it wasn't previously present in the lockfile)
          lockfile_body.gsub(
            LOCKFILE_ENDING,
            lockfile.content.match(LOCKFILE_ENDING)&.[](:ending) || "\n"
          )
        end

        def sanitized_gemspec_content(gemspec_content)
          new_version = replacement_version_for_gemspec(gemspec_content)

          GemspecSanitizer.
            new(replacement_version: new_version).
            rewrite(gemspec_content)
        end

        def replacement_version_for_gemspec(gemspec_content)
          return "0.0.1" unless lockfile

          gemspec_specs =
            ::Bundler::LockfileParser.new(sanitized_lockfile_body).specs.
            select { |s| gemspec_sources.include?(s.source.class) }

          gem_name =
            GemspecDependencyNameFinder.new(gemspec_content: gemspec_content).
            dependency_name

          return gemspec_specs.first&.version || "0.0.1" unless gem_name

          spec = gemspec_specs.find { |s| s.name == gem_name }
          spec&.version || gemspec_specs.first&.version || "0.0.1"
        end

        def relevant_credentials
          credentials.
            select { |cred| cred["password"] || cred["token"] }.
            select do |cred|
              next true if cred["type"] == "git_source"
              next true if cred["type"] == "rubygems_server"

              false
            end
        end

        def prepared_gemfile_content(file)
          content =
            GemfileUpdater.new(
              dependencies: dependencies,
              gemfile: file
            ).updated_gemfile_content
          return content if @dont_lock_ruby_version

          top_level_gemspecs.each do |gs|
            content = RubyRequirementSetter.new(gemspec: gs).rewrite(content)
          end

          content
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

        def gemfile
          @gemfile ||= dependency_files.find { |f| f.name == "Gemfile" } ||
                       dependency_files.find { |f| f.name == "gems.rb" }
        end

        def lockfile
          @lockfile ||=
            dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        def sanitized_lockfile_body
          lockfile.content.gsub(LOCKFILE_ENDING, "")
        end

        def evaled_gemfiles
          @evaled_gemfiles ||=
            dependency_files.
            reject { |f| f.name.end_with?(".gemspec") }.
            reject { |f| f.name.end_with?(".specification") }.
            reject { |f| f.name.end_with?(".lock") }.
            reject { |f| f.name.end_with?(".ruby-version") }.
            reject { |f| f.name == "Gemfile" }.
            reject { |f| f.name == "gems.rb" }.
            reject { |f| f.name == "gems.locked" }.
            reject(&:support_file?)
        end

        def specification_files
          dependency_files.select { |f| f.name.end_with?(".specification") }
        end

        def set_bundler_flags_and_credentials
          # Set auth details
          relevant_credentials.each do |cred|
            token = cred["token"] ||
                    "#{cred['username']}:#{cred['password']}"

            ::Bundler.settings.set_command_option(
              cred.fetch("host"),
              token.gsub("@", "%40F").gsub("?", "%3F")
            )
          end

          # Use HTTPS for GitHub if lockfile was generated by Bundler 2
          set_bundler_2_flags if using_bundler_2?
        end

        def set_bundler_2_flags
          ::Bundler.settings.set_command_option("forget_cli_options", "true")
          ::Bundler.settings.set_command_option("github.https", "true")
        end

        def git_dependency?(dep)
          GitCommitChecker.new(
            dependency: dep,
            credentials: credentials
          ).git_dependency?
        end

        def using_bundler_2?
          return unless lockfile

          lockfile.content.match?(/BUNDLED WITH\s+2/m)
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
