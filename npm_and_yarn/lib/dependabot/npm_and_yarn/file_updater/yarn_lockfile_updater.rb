# typed: true
# frozen_string_literal: true

require "uri"

require "dependabot/npm_and_yarn"
require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class YarnLockfileUpdater
        require_relative "npmrc_builder"
        require_relative "package_json_updater"
        require_relative "package_json_preparer"

        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @error_handler = YarnErrorHandler.new(
            dependencies: dependencies,
            dependency_files: dependency_files
          )
        end

        def updated_yarn_lock_content(yarn_lock)
          @updated_yarn_lock_content ||= {}
          return @updated_yarn_lock_content[yarn_lock.name] if @updated_yarn_lock_content[yarn_lock.name]

          new_content = updated_yarn_lock(yarn_lock)

          @updated_yarn_lock_content[yarn_lock.name] =
            post_process_yarn_lockfile(new_content)
        end

        private

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :repo_contents_path
        attr_reader :credentials
        attr_reader :error_handler

        def top_level_dependencies
          dependencies.select(&:top_level?)
        end

        def sub_dependencies
          dependencies.reject(&:top_level?)
        end

        def updated_yarn_lock(yarn_lock)
          base_dir = dependency_files.first.directory
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            write_temporary_dependency_files(yarn_lock)
            lockfile_name = Pathname.new(yarn_lock.name).basename.to_s
            path = Pathname.new(yarn_lock.name).dirname.to_s
            updated_files = run_current_yarn_update(
              path: path,
              yarn_lock: yarn_lock
            )
            updated_files.fetch(lockfile_name)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_yarn_lock_updater_error(e, yarn_lock)
        end

        def run_current_yarn_update(path:, yarn_lock:)
          top_level_dependency_updates = top_level_dependencies.map do |d|
            {
              name: d.name,
              version: d.version,
              requirements: requirements_for_path(d.requirements, path)
            }
          end

          run_yarn_updater(
            path: path,
            yarn_lock: yarn_lock,
            top_level_dependency_updates: top_level_dependency_updates
          )
        end

        def run_previous_yarn_update(path:, yarn_lock:)
          previous_top_level_dependencies = top_level_dependencies.map do |d|
            {
              name: d.name,
              version: d.previous_version,
              requirements: requirements_for_path(
                d.previous_requirements, path
              )
            }
          end

          run_yarn_updater(
            path: path,
            yarn_lock: yarn_lock,
            top_level_dependency_updates: previous_top_level_dependencies
          )
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def run_yarn_updater(path:, yarn_lock:, top_level_dependency_updates:)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              if top_level_dependency_updates.any?
                if Helpers.yarn_berry?(yarn_lock)
                  run_yarn_berry_top_level_updater(top_level_dependency_updates: top_level_dependency_updates,
                                                   yarn_lock: yarn_lock)
                else

                  run_yarn_top_level_updater(
                    top_level_dependency_updates: top_level_dependency_updates
                  )
                end
              elsif Helpers.yarn_berry?(yarn_lock)
                run_yarn_berry_subdependency_updater(yarn_lock: yarn_lock)
              else
                run_yarn_subdependency_updater(yarn_lock: yarn_lock)
              end
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          package_missing = error_handler.package_missing(e.message)

          unless package_missing
            error_handler.handle_error(e, {
              yarn_lock: yarn_lock
            })
          end

          raise unless package_missing

          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 2

          sleep(rand(3.0..10.0))
          retry
        end

        # rubocop:enable Metrics/PerceivedComplexity

        def run_yarn_berry_top_level_updater(top_level_dependency_updates:, yarn_lock:)
          write_temporary_dependency_files(yarn_lock)
          # If the requirements have changed, it means we've updated the
          # package.json file(s), and we can just run yarn install to get the
          # lockfile in the right state. Otherwise we'll need to manually update
          # the lockfile.

          if top_level_dependency_updates.all? { |dep| requirements_changed?(dep[:name]) }
            Helpers.run_yarn_command("install #{yarn_berry_args}".strip)
          else
            updates = top_level_dependency_updates.collect do |dep|
              dep[:name]
            end

            Helpers.run_yarn_command(
              "up -R #{updates.join(' ')} #{yarn_berry_args}".strip,
              fingerprint: "up -R <dependency_names> #{yarn_berry_args}".strip
            )
          end
          { yarn_lock.name => File.read(yarn_lock.name) }
        end

        def requirements_changed?(dependency_name)
          dep = top_level_dependencies.first { |d| d.name == dependency_name }
          dep.requirements != dep.previous_requirements
        end

        def run_yarn_berry_subdependency_updater(yarn_lock:)
          dep = sub_dependencies.first
          update = "#{dep.name}@#{dep.version}"

          commands = [
            ["add #{update} #{yarn_berry_args}".strip, "add <update> #{yarn_berry_args}".strip],
            ["dedupe #{dep.name} #{yarn_berry_args}".strip, "dedupe <dep_name> #{yarn_berry_args}".strip],
            ["remove #{dep.name} #{yarn_berry_args}".strip, "remove <dep_name> #{yarn_berry_args}".strip]
          ]

          Helpers.run_yarn_commands(*commands)
          { yarn_lock.name => File.read(yarn_lock.name) }
        end

        def yarn_berry_args
          @yarn_berry_args ||= Helpers.yarn_berry_args
        end

        def run_yarn_top_level_updater(top_level_dependency_updates:)
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "yarn:update",
            args: [
              Dir.pwd,
              top_level_dependency_updates
            ]
          )
        end

        def run_yarn_subdependency_updater(yarn_lock:)
          lockfile_name = Pathname.new(yarn_lock.name).basename.to_s
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "yarn:updateSubdependency",
            args: [Dir.pwd, lockfile_name, sub_dependencies.map(&:to_h)]
          )
        end

        def requirements_for_path(requirements, path)
          return requirements if path.to_s == "."

          requirements.filter_map do |r|
            next unless r[:file].start_with?("#{path}/")

            r.merge(file: r[:file].gsub(/^#{Regexp.quote("#{path}/")}/, ""))
          end
        end

        def handle_yarn_lock_updater_error(error, yarn_lock)
          error_message = error.message

          error_handler.handle_error(error, {
            yarn_lock: yarn_lock
          })

          package_not_found = error_handler.handle_package_not_found(error_message, yarn_lock)

          if package_not_found.any?
            sanitized_name = package_not_found[:sanitized_name]
            sanitized_message = package_not_found[:sanitized_message]
            handle_missing_package(sanitized_name, sanitized_message, yarn_lock)
          end

          # TODO: Move this logic to the version resolver and check if a new
          # version and all of its subdependencies are resolvable

          # Make sure the error in question matches the current list of
          # dependencies or matches an existing scoped package, this handles the
          # case where a new version (e.g. @angular-devkit/build-angular) relies
          # on a added dependency which hasn't been published yet under the same
          # scope (e.g. @angular-devkit/build-optimizer)
          #
          # This seems to happen when big monorepo projects publish all of their
          # packages sequentially, which might take enough time for Dependabot
          # to hear about a new version before all of its dependencies have been
          # published
          #
          # OR
          #
          # This happens if a new version has been published but npm is having
          # consistency issues and the version isn't fully available on all
          # queries
          if error_message.start_with?(DEPENDENCY_NO_VERSION_FOUND) &&
             dependencies_in_error_message?(error_message) &&
             resolvable_before_update?(yarn_lock)

            # Raise a bespoke error so we can capture and ignore it if
            # we're trying to create a new PR (which will be created
            # successfully at a later date)
            raise Dependabot::InconsistentRegistryResponse, error_message
          end

          handle_timeout(error_message, yarn_lock) if error_message.match?(
            TIMEOUT_FETCHING_PACKAGE_REGEX
          )

          if error_message.start_with?(DEPENDENCY_VERSION_NOT_FOUND) ||
             error_message.include?(DEPENDENCY_NOT_FOUND) ||
             error_message.include?(DEPENDENCY_MATCH_NOT_FOUND)

            unless resolvable_before_update?(yarn_lock)
              error_handler.raise_resolvability_error(error_message, yarn_lock)
            end

            # Dependabot has probably messed something up with the update and we
            # want to hear about it
            raise error
          end

          raise error
        end

        def resolvable_before_update?(yarn_lock)
          @resolvable_before_update ||= {}
          return @resolvable_before_update[yarn_lock.name] if @resolvable_before_update.key?(yarn_lock.name)

          @resolvable_before_update[yarn_lock.name] =
            begin
              base_dir = dependency_files.first.directory
              SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
                write_temporary_dependency_files(yarn_lock, update_package_json: false)
                path = Pathname.new(yarn_lock.name).dirname.to_s
                run_previous_yarn_update(path: path, yarn_lock: yarn_lock)
              end

              true
            rescue SharedHelpers::HelperSubprocessFailed
              false
            end
        end

        def dependencies_in_error_message?(message)
          names = dependencies.map { |dep| dep.name.split("/").first }
          # Example format: Couldn't find any versions for
          # "@dependabot/dummy-pkg-b" that matches "^1.3.0"
          names.any? do |name|
            message.match?(%r{"#{Regexp.quote(name)}["\/]})
          end
        end

        def write_temporary_dependency_files(yarn_lock, update_package_json: true)
          write_lockfiles

          if Helpers.yarn_berry?(yarn_lock) && yarnrc_yml_file
            yarnrc_yml_sanitize_content = sanitize_yarnrc_content(yarnrc_yml_content)
            File.write(".yarnrc.yml", yarnrc_yml_sanitize_content)
          else
            File.write(".npmrc", npmrc_content)
            File.write(".yarnrc", yarnrc_content) if yarnrc_specifies_private_reg?
          end

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)

            updated_content =
              if update_package_json && top_level_dependencies.any?
                updated_package_json_content(file)
              else
                file.content
              end

            updated_content = package_json_preparer(updated_content).prepared_content
            File.write(file.name, updated_content)
          end

          clean_npmrc_in_path(yarn_lock)
        end

        def sanitize_yarnrc_content(content)
          # Replace all "${...}" and ${...} occurrences with dummy strings. We use
          # dummy strings instead of empty strings to prevent issues with npmAlwaysAuth
          content.gsub(/"\$\{.*?}"/, '"DUMMYCREDS"').gsub(/\$\{.*?}/, '"DUMMYCREDS"')
        end

        def clean_npmrc_in_path(yarn_lock)
          # Berry does not read npmrc files.
          return if Helpers.yarn_berry?(yarn_lock)

          # Find .npmrc files in parent directories and remove variables in them
          # to avoid errors when running yarn 1.
          dirs = Dir.getwd.split("/")
          dirs.pop
          while dirs.any?
            npmrc = dirs.join("/") + "/.npmrc"
            if File.exist?(npmrc)
              # If the .npmrc file exists, clean it
              File.write(npmrc, File.read(npmrc).gsub(/\$\{.*?\}/, ""))
            end
            dirs.pop
          end
        end

        def write_lockfiles
          yarn_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
        end

        def git_ssh_requirements_to_swap
          return @git_ssh_requirements_to_swap if @git_ssh_requirements_to_swap

          @git_ssh_requirements_to_swap = package_files.flat_map do |file|
            package_json_preparer(file.content).swapped_ssh_requirements
          end
        end

        def post_process_yarn_lockfile(lockfile_content)
          updated_content = lockfile_content

          git_ssh_requirements_to_swap.each do |req|
            new_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
            updated_content = updated_content.gsub(new_req, req)
          end

          # Enforce https for most common hostnames
          updated_content = updated_content.gsub(
            %r{http://(.*?(?:yarnpkg\.com|npmjs\.org|npmjs\.com))/},
            'https://\1/'
          )

          updated_content = remove_integrity_lines(updated_content) if remove_integrity_lines?

          updated_content
        end

        def remove_integrity_lines?
          yarn_locks.none? { |f| f.content.include?(" integrity sha") }
        end

        def remove_integrity_lines(content)
          content.lines.reject { |l| l.match?(/\s*integrity sha/) }.join
        end

        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= {}
          @lockfile_dependencies[lockfile.name] ||=
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        def handle_missing_package(package_name, error_message, yarn_lock)
          missing_dep = lockfile_dependencies(yarn_lock)
                        .find { |dep| dep.name == package_name }

          error_handler.raise_resolvability_error(error_message, yarn_lock) unless missing_dep

          reg = NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: npmrc_file,
            yarnrc_file: yarnrc_file,
            yarnrc_yml_file: yarnrc_yml_file
          ).registry

          return if UpdateChecker::RegistryFinder.central_registry?(reg) && !package_name.start_with?("@")

          raise PrivateSourceAuthenticationFailure, reg
        end

        def handle_timeout(error_message, yarn_lock)
          url = error_message.match(TIMEOUT_FETCHING_PACKAGE_REGEX)
                             .named_ # rubocop:enable Metrics/ClassLength#RI(url).host == NPM_REGISTERY

          package_name = error_message.match(TIMEOUT_FETCHING_PACKAGE_REGEX)
                                      .named_captures["package"]
          sanitized_name = sanitize_package_name(package_name)

          dep = lockfile_dependencies(yarn_lock)
                .find { |d| d.name == sanitized_name }
          return unless dep

          raise PrivateSourceTimedOut, url.gsub(
            HTTP_CHECK_REGEX,
            ""
          )
        end

        def npmrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        def updated_package_json_content(file)
          PackageJsonUpdater.new(
            package_json: file,
            dependencies: top_level_dependencies
          ).updated_package_json.content
        end

        def package_json_preparer(content)
          @package_json_preparer ||= {}
          @package_json_preparer[content] ||=
            PackageJsonPreparer.new(
              package_json_content: content
            )
        end

        def npmrc_disables_lockfile?
          npmrc_content.match?(/^package-lock\s*=\s*false/)
        end

        def yarnrc_specifies_private_reg?
          return false unless yarnrc_file

          regex = UpdateChecker::RegistryFinder::YARN_GLOBAL_REGISTRY_REGEX
          yarnrc_global_registry =
            yarnrc_file.content
                       .lines.find { |line| line.match?(regex) }
                       &.match(regex)
                       &.named_captures
                       &.fetch("registry")

          return false unless yarnrc_global_registry

          UpdateChecker::RegistryFinder::CENTRAL_REGISTRIES.any? do |r|
            r.include?(URI(yarnrc_global_registry).host)
          end
        end

        def yarnrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).yarnrc_content
        end

        def sanitize_package_name(package_name)
          package_name.gsub("%2f", "/").gsub("%2F", "/")
        end

        def yarn_locks
          @yarn_locks ||=
            dependency_files
            .select { |f| f.name.end_with?("yarn.lock") }
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def yarnrc_file
          dependency_files.find { |f| f.name == ".yarnrc" }
        end

        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end

        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
        end

        def yarnrc_yml_content
          yarnrc_yml_file.content
        end
      end
    end

    class YarnErrorHandler
      extend T::Sig

      # Initializes the YarnErrorHandler with dependencies and dependency files
      sig do
        params(
          dependencies: T::Array[Dependabot::Dependency],
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).void
      end
      def initialize(dependencies:, dependency_files:)
        @dependencies = dependencies
        @dependency_files = dependency_files
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      public

      # Extracts "Usage Error:" messages from error messages
      sig { params(error_message: String).returns(T.nilable(String)) }
      def find_usage_error(error_message)
        start_index = error_message.rindex(YARN_USAGE_ERROR_TEXT)
        return nil unless start_index

        error_details = error_message[start_index..-1]
        error_details&.strip
      end

      # Main error handling method
      sig { params(error: SharedHelpers::HelperSubprocessFailed, params: T::Hash[Symbol, String]).void }
      def handle_error(error, params)
        error_message = error.message

        # Extract the usage error message from the raw error message
        usage_error_message = find_usage_error(error_message) || ""

        # Check if the error message contains any group patterns and raise the corresponding error class
        handle_group_patterns(error, usage_error_message, params)

        # Check if defined yarn error codes contained in the error message
        # and raise the corresponding error class
        handle_yarn_error(error, params)
      end

      # Handles errors with specific to yarn error codes
      sig { params(error: SharedHelpers::HelperSubprocessFailed, params: T::Hash[Symbol, String]).void }
      def handle_yarn_error(error, params)
        ## Clean error message from ANSI escape codes
        error_message = error.message.gsub(/\e\[\d+(;\d+)*m/, "")
        matches = error_message.scan(YARN_CODE_REGEX)
        return if matches.empty?

        # Go through each match backwards in the error message and raise the corresponding error class
        matches.reverse_each do |match|
          code = match[0]
          next unless code

          yarn_error = YARN_ERROR_CODES[code]
          next unless yarn_error.is_a?(Hash)

          message = yarn_error[:message]
          handler = yarn_error[:handler]
          next unless handler

          modified_error_message = if message
                                     "[#{code}]: #{message}, Detail: #{error_message}"
                                   else
                                     "[#{code}]: #{error_message}"
                                   end

          raise  create_error(handler, modified_error_message, error, params)
        end
      end

      # Handles errors based on group patterns
      sig do
        params(
          error: SharedHelpers::HelperSubprocessFailed,
          usage_error_message: String,
          params: T::Hash[Symbol, String]
        ).void
      end
      def handle_group_patterns(error, usage_error_message, params) # rubocop:disable Metrics/PerceivedComplexity
        error_message = error.message
        VALIDATION_GROUP_PATTERNS.each do |group|
          patterns = group[:patterns]
          matchfn = group[:matchfn]
          handler = group[:handler]
          in_usage = group[:in_usage] || false

          next unless (patterns || matchfn) && handler

          message = usage_error_message.empty? ? error_message : usage_error_message
          if in_usage && pattern_in_message(patterns, usage_error_message)
            raise create_error(handler, message, error, params)
          elsif !in_usage && pattern_in_message(patterns, error.message)
            raise create_error(handler, error.message, error, params)
          end

          raise create_error(handler, message, error, params) if matchfn&.call(usage_error_message, error_message)
        end
      end

      # Creates a new error based on the provided parameters
      sig do
        params(
          handler: ErrorHandler,
          message: String,
          error: SharedHelpers::HelperSubprocessFailed,
          params: T::Hash[Symbol, String]
        ).returns(Dependabot::DependabotError)
      end
      def create_error(handler, message, error, params)
        handler.call(message, error, {
          dependencies: dependencies,
          dependency_files: dependency_files,
          **params
        })
      end

      # Raises a resolvability error for a dependency file
      sig do
        params(
          error_message: String,
          yarn_lock: Dependabot::DependencyFile
        ).void
      end
      def raise_resolvability_error(error_message, yarn_lock)
        dependency_names = dependencies.map(&:name).join(", ")
        msg = "Error whilst updating #{dependency_names} in #{yarn_lock.path}:\n#{error_message}"
        raise Dependabot::DependencyFileNotResolvable, msg
      end

      # Checks if a pattern is in a message
      sig do
        params(
          patterns: T::Array[T.any(String, Regexp)],
          message: String
        ).returns(T::Boolean)
      end
      def pattern_in_message(patterns, message)
        patterns.each do |pattern|
          if pattern.is_a?(String)
            return true if message.include?(pattern)
          elsif pattern.is_a?(Regexp)
            return true if message.gsub(/\e\[[\d;]*[A-Za-z]/, "").match?(pattern)
          end
        end
        false
      end

      sig do
        params(error_message: String, yarn_lock: Dependabot::DependencyFile)
          .returns(T::Hash[T.any(Symbol, String), T.any(String, NilClass)])
      end
      def handle_package_not_found(error_message, yarn_lock) # rubocop:disable Metrics/PerceivedComplexity
        # There are 2 different package not found error messages
        package_not_found = error_message.include?(PACKAGE_NOT_FOUND)
        package_not_found2 = error_message.match?(PACKAGE_NOT_FOUND2)

        # If non of the patterns are found, return an empty hash
        return {} unless package_not_found || package_not_found2

        sanitized_name = T.let(nil, T.nilable(String))

        if package_not_found
          package_name =
            error_message
            .match(PACKAGE_NOT_FOUND_PACKAGE_NAME_REGEX)
            &.named_captures
            &.[](PACKAGE_NOT_FOUND_PACKAGE_NAME_CAPTURE)
            &.split(PACKAGE_NOT_FOUND_PACKAGE_NAME_CAPTURE_SPLIT_REGEX)
            &.first
        end

        if package_not_found2
          package_name =
            error_message
            .match(PACKAGE_NOT_FOUND2_PACKAGE_NAME_REGEX)
            &.named_captures
            &.[](PACKAGE_NOT_FOUND2_PACKAGE_NAME_CAPTURE)
        end

        raise_resolvability_error(error_message, yarn_lock) unless package_name
        sanitized_name = sanitize_package_name(package_name) if package_name
        error_message = error_message.gsub(package_name, sanitized_name) if package_name && sanitized_name
        { sanitized_name: sanitized_name, sanitized_message: error_message }
      end

      # Checks if a package is missing from the error message
      sig { params(error_message: String).returns(T::Boolean) }
      def package_missing(error_message)
        names = dependencies.map(&:name)
        package_missing = names.any? { |name| error_message.include?("find package \"#{name}") }
        !!error_message.match(PACKAGE_MISSING_REGEX) || package_missing
      end

      sig { params(package_name: T.nilable(String)).returns(T.nilable(String)) }
      def sanitize_package_name(package_name)
        return package_name.gsub("%2f", "/").gsub("%2F", "/") if package_name

        nil
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
