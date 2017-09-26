# frozen_string_literal: true

require "bundler_definition_version_patch"
require "bundler_git_source_patch"
require "excon"
require "gems"
require "gemnasium/parser"
require "dependabot/file_updaters/ruby/bundler"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        require "dependabot/update_checkers/ruby/bundler/requirements_updater"

        GIT_REF_REGEX = /git reset --hard [^\s]*` in directory (?<path>[^\s]*)/

        def latest_version
          if dependency_source.instance_of?(::Bundler::Source::Git)
            latest_version_details&.fetch(:commit_sha)
          else
            latest_version_details&.fetch(:version)
          end
        end

        def latest_resolvable_version
          if dependency_source.instance_of?(::Bundler::Source::Git)
            latest_resolvable_version_details&.fetch(:commit_sha)
          else
            latest_resolvable_version_details&.fetch(:version)
          end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            existing_version: dependency.version,
            latest_version: latest_version_details&.fetch(:version)&.to_s,
            latest_resolvable_version:
              latest_resolvable_version_details&.fetch(:version)&.to_s
          ).updated_requirements
        end

        private

        def latest_version_details
          @latest_version_details ||= fetch_latest_version_details
        end

        def latest_resolvable_version_details
          @latest_resolvable_version_details ||=
            fetch_latest_resolvable_version_details
        end

        def fetch_latest_version_details
          case dependency_source
          when NilClass then latest_rubygems_version_details
          when ::Bundler::Source::Rubygems
            latest_private_version_details
          when ::Bundler::Source::Git
            latest_git_version_details
          end
        end

        def fetch_latest_resolvable_version_details
          return latest_version_details unless gemfile

          in_a_temporary_bundler_context do
            definition = ::Bundler::Definition.build(
              "Gemfile",
              lockfile&.name,
              gems: [dependency.name]
            )

            if dependency_source.instance_of?(::Bundler::Source::Git)
              begin
                definition.resolve_remotely!
                dep = definition.resolve.find { |d| d.name == dependency.name }
                { version: dep.version, commit_sha: dep.source.revision }
              rescue ::Bundler::VersionConflict
                #
                { version: nil, commit_sha: nil }
              end
            else
              definition.resolve_remotely!
              dep = definition.resolve.find { |d| d.name == dependency.name }
              { version: dep.version }
            end
          end
        end

        def dependency_source
          return nil unless gemfile

          @dependency_source ||=
            in_a_temporary_bundler_context do
              ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
                find { |dep| dep.name == dependency.name }&.source
            end
        end

        def latest_rubygems_version_details
          latest_info = Gems.info(dependency.name)

          return nil if latest_info["version"].nil?

          # Rubygems excludes pre-releases from the `Gems.info` response,
          # so no need to filter them out.
          {
            version: Gem::Version.new(latest_info["version"]),
            sha: latest_info["sha"]
          }
        rescue JSON::ParserError
          nil
        end

        def latest_private_version_details
          spec =
            dependency_source.
            fetchers.flat_map do |fetcher|
              fetcher.
                specs_with_retry([dependency.name], dependency_source).
                search_all(dependency.name).
                reject { |s| s.version.prerelease? }
            end.
            sort_by(&:version).last
          { version: spec.version }
        rescue ::Bundler::Fetcher::AuthenticationRequiredError => error
          regex = /bundle config (?<repo>.*) username:password/
          source = error.message.match(regex)[:repo]
          raise Dependabot::PrivateSourceNotReachable, source
        end

        def latest_git_version_details
          in_a_temporary_bundler_context do
            source =
              ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
              find { |dep| dep.name == dependency.name }.source

            # Tell Bundler we're fine with fetching the source remotely
            source.instance_variable_set(:@allow_remote, true)
            spec = source.specs.first

            { version: spec.version, commit_sha: spec.source.revision }
          end
        end

        #########################
        # Bundler context setup #
        #########################

        # All methods below this line are used solely to set the Bundler
        # context. In future, they are a strong candidate to be refactored out
        # into a helper class.

        def in_a_temporary_bundler_context(error_handling: true)
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              # Remove installed gems from the default Rubygems index
              ::Gem::Specification.all = []

              # Set auth details for GitHub
              ::Bundler.settings.set_command_option(
                "github.com",
                "x-access-token:#{github_access_token}"
              )

              yield
            end
          end
        rescue SharedHelpers::ChildProcessFailed => error
          raise unless error_handling

          # Raise more descriptive errors
          handle_bundler_errors(error)
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/AbcSize
        def handle_bundler_errors(error)
          msg = error.error_class + " with message: " + error.error_message

          case error.error_class
          when "Bundler::Dsl::DSLError"
            # We couldn't evaluate the Gemfile, let alone resolve it
            raise Dependabot::DependencyFileNotEvaluatable, msg
          when "Bundler::Source::Git::MissingGitRevisionError"
            raise GitDependencyReferenceNotFound, dependency.name
          when "Bundler::Source::Git::GitCommandError"
            if error.error_message.match?(GIT_REF_REGEX)
              # We couldn't find the specified branch / commit (or the two
              # weren't compatible).
              gem_name =
                error.error_message.match(GIT_REF_REGEX).named_captures["path"].
                split("/").last.split("-")[0..-2].join
              raise GitDependencyReferenceNotFound, gem_name
            end

            bad_uris = inaccessible_git_dependencies.map { |s| s.source.uri }
            raise unless bad_uris.any?

            # We don't have access to one of repos required
            raise Dependabot::GitDependenciesNotReachable, bad_uris
          when "Bundler::GemNotFound", "Gem::InvalidSpecificationException",
               "Bundler::VersionConflict"
            # Bundler threw an error during resolution. Any of:
            # - the gem doesn't exist in any of the specified sources
            # - the gem wasn't specified properly
            # - the gem was specified at an incompatible version
            raise Dependabot::DependencyFileNotResolvable, msg
          when "RuntimeError"
            raise unless error.error_message.include?("Unable to find a spec")
            raise DependencyFileNotResolvable, msg
          else raise
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/AbcSize

        def inaccessible_git_dependencies
          in_a_temporary_bundler_context(error_handling: false) do
            ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
              reject do |spec|
                next true unless spec.source.is_a?(::Bundler::Source::Git)

                # Piggy-back off some private Bundler methods to configure the
                # URI with auth details in the same way Bundler does.
                git_proxy = spec.source.send(:git_proxy)
                uri = git_proxy.send(:configured_uri_for, spec.source.uri)
                uri += ".git" unless uri.end_with?(".git")
                uri += "/info/refs?service=git-upload-pack"
                Excon.get(uri, middlewares: SharedHelpers.excon_middleware).
                  status == 200
              end
          end
        end

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

        def write_temporary_dependency_files
          File.write("Gemfile", gemfile_for_update_check) if gemfile
          File.write("Gemfile.lock", lockfile.content) if lockfile

          write_updated_gemspec if gemspec
          write_ruby_version_file if ruby_version_file

          path_gemspecs.compact.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file.content))
          end
        end

        def gemfile_for_update_check
          content = update_dependency_requirement(gemfile.content)
          content
        end

        def write_updated_gemspec
          path = gemspec.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, sanitized_gemspec_content(updated_gemspec_content))
        end

        def write_ruby_version_file
          path = ruby_version_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, ruby_version_file.content)
        end

        def updated_gemspec_content
          return gemspec.content unless original_gemspec_declaration_string
          gemspec.content.gsub(
            original_gemspec_declaration_string,
            updated_gemspec_declaration_string
          )
        end

        def original_gemspec_declaration_string
          @original_gemspec_declaration_string ||=
            begin
              matches = []
              regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX
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
        def update_dependency_requirement(gemfile_content)
          unless gemfile_content.
                 to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
                 find { Regexp.last_match[:name] == dependency.name }
            return gemfile_content
          end

          replacement_version =
            if dependency.version&.match?(/^[0-9a-f]{40}$/)
              0
            else
              dependency.version || 0
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
