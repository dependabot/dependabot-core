# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/bun/helpers"
require "dependabot/bun/package/registry_finder"
require "dependabot/bun/registry_parser"
require "dependabot/package/npm_package_json"
require "dependabot/shared_helpers"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      class BunLockfileUpdater
        extend T::Sig

        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def updated_bun_lock_content(bun_lock)
          @updated_bun_lock_content ||= T.let({}, T.nilable(T::Hash[String, String]))
          return T.must(@updated_bun_lock_content[bun_lock.name]) if @updated_bun_lock_content[bun_lock.name]

          new_content = run_bun_update(bun_lock: bun_lock)
          @updated_bun_lock_content[bun_lock.name] = new_content
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_bun_lock_updater_error(e, bun_lock)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        ERR_PATTERNS = T.let(
          {
            /get .* 404/i => Dependabot::DependencyNotFound,
            /installfailed cloning repository/i => Dependabot::DependencyNotFound,
            /file:.* failed to resolve/i => Dependabot::DependencyNotFound,
            /no version matching/i => Dependabot::DependencyFileNotResolvable,
            /failed to resolve/i => Dependabot::DependencyFileNotResolvable
          }.freeze,
          T::Hash[Regexp, Dependabot::DependabotError]
        )

        # A registry rejected the request for a package or its tarball. bun prints
        # `error: failed to download <name>@<version>: <status> <reason>` with the tarball URL on the next line, or
        # `error: GET <url> - <status>` when the request for the package metadata fails.
        DOWNLOAD_FAILED =
          %r{error: failed to download (?<spec>\S+): (?<status>\d{3})[^\n]*(?:\n[[:space:]]*(?<url>https?://\S+))?}
        REQUEST_FAILED = %r{error: GET (?<url>https?://\S+) - (?<status>\d{3})\b}
        ACCESS_DENIED_STATUSES = %w(401 403).freeze
        NOT_FOUND_STATUS = "404"

        # A workspace that bun.lock or package.json refers to is not part of the checkout
        WORKSPACE_NOT_ON_DISK =
          /
            error:\s(?:the\sroot\spackage|workspace\s"[^"]+")\s
            depends\son\sworkspace\s"(?<name>[^"]+)"\s\((?<path>[^)]*)\),\s
            which\sis\slisted\sin\sbun\.lock\sbut\snot\son\sdisk
          /x
        WORKSPACE_NOT_FOUND = /error: Workspace not found "(?<path>[^"]+)"/

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def run_bun_update(bun_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(bun_lock))

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_bun_updater

              write_final_package_json_files

              run_bun_install

              File.read(bun_lock.name)
            end
          end
        end

        sig { void }
        def run_bun_updater
          dependency_updates_by_target.each do |workspace_name, deps|
            dependency_updates = deps.map { |d| "#{d.name}@#{d.version}" }

            command = T.let(["install", *dependency_updates], T::Array[String])
            command += ["--filter", workspace_name] if workspace_name
            command += ["--save-text-lockfile", "--ignore-scripts"]

            Helpers.run_bun_command(
              command,
              fingerprint: "install <dependency_updates> --save-text-lockfile --ignore-scripts"
            )
          end
        end

        # Maps each install target (nil for the repo root, or a workspace
        # path) to the dependencies that need installing there. A dependency
        # declared in multiple manifests must be installed in each one, since
        # Bun merges same-name declarations into a single Dependency.
        sig { returns(T::Hash[T.nilable(String), T::Array[Dependabot::Dependency]]) }
        def dependency_updates_by_target
          dependencies
            .flat_map { |dependency| install_targets_for(dependency).map { |target| [target, dependency] } }
            .group_by { |target, _dependency| target }
            .transform_values { |pairs| pairs.map { |_target, dependency| dependency } }
        end

        # Returns every install target (nil for the repo root, or a workspace
        # path) that declares +dependency+. Falls back to an unfiltered root
        # install if it isn't declared anywhere (e.g. a sub-dependency).
        sig { params(dependency: Dependabot::Dependency).returns(T::Array[T.nilable(String)]) }
        def install_targets_for(dependency)
          root = root_package_json

          workspace_targets = package_files.filter_map do |file|
            next if file == root
            next unless package_json_declares?(file, dependency)

            workspace_filter(file)
          end.uniq

          declared_at_root = !root || package_json_declares?(root, dependency)
          return workspace_targets if !declared_at_root && workspace_targets.any?

          [nil, *workspace_targets]
        end

        # Path-based --filter target for the workspace at +file+ (e.g.
        # "./packages/app"). Bun's --filter also accepts a package's declared
        # "name", but names can contain glob metacharacters that would match
        # unrelated workspaces, so a path is used instead.
        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def workspace_filter(file)
          unless Dependabot::Package::NpmPackageJson.from_file(file).name
            raise Dependabot::DependencyFileNotParseable.new(
              file.path,
              "#{file.name} must declare a \"name\" to be targeted for a workspace-scoped update"
            )
          end

          "./#{File.dirname(file.name)}"
        end

        sig do
          params(package_json_file: Dependabot::DependencyFile, dependency: Dependabot::Dependency)
            .returns(T::Boolean)
        end
        def package_json_declares?(package_json_file, dependency)
          declared = T.let(false, T::Boolean)
          Dependabot::Package::NpmPackageJson.from_file(package_json_file).each_dependency do |name, _req, _type|
            declared ||= name == dependency.name
          end
          declared
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_package_json
          package_files.find { |f| f.name == "package.json" }
        end

        sig { void }
        def run_bun_install
          Helpers.run_bun_command(
            "install --save-text-lockfile --ignore-scripts"
          )
        end

        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Dependency]]))
          @lockfile_dependencies[lockfile.name] ||=
            Bun::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        sig { params(error: Dependabot::DependabotError, bun_lock: Dependabot::DependencyFile).returns(T.noreturn) }
        def handle_bun_lock_updater_error(error, bun_lock)
          error_message = error.message

          raise_registry_error(error_message)
          raise_workspace_error(error_message, bun_lock)

          ERR_PATTERNS.each do |pattern, error_class|
            raise error_class, error_message if error_message.match?(pattern)
          end

          raise error
        end

        # Reports the first registry failure bun printed that the repository has to resolve: access that was denied,
        # or a tarball the registry does not have. A failure with any other status is skipped, so it cannot hide a
        # later one that can be classified, and is left to the generic handling when there is none.
        sig { params(error_message: String).void }
        def raise_registry_error(error_message)
          registry_failures(error_message).each do |failure|
            status = failure[:status]
            url = failure[:url]

            if ACCESS_DENIED_STATUSES.include?(status) && url
              raise Dependabot::PrivateSourceAuthenticationFailure, registry_origin(url)
            end

            next unless status == NOT_FOUND_STATUS && failure.names.include?("spec")

            raise Dependabot::DependencyNotFound, package_name_from(T.must(failure[:spec]))
          end
        end

        # Every registry failure in the output, in the order bun printed them
        sig { params(error_message: String).returns(T::Array[MatchData]) }
        def registry_failures(error_message)
          [DOWNLOAD_FAILED, REQUEST_FAILED]
            .flat_map { |pattern| error_message.to_enum(:scan, pattern).map { T.must(Regexp.last_match) } }
            .sort_by { |match| match.begin(0) }
        end

        sig { params(error_message: String, bun_lock: Dependabot::DependencyFile).void }
        def raise_workspace_error(error_message, bun_lock)
          if (match = error_message.match(WORKSPACE_NOT_ON_DISK))
            raise Dependabot::DependencyFileNotResolvable,
                  "#{bun_lock.path} lists the workspace \"#{match[:name]}\" (#{match[:path]}), " \
                  "but it is not part of the repository. Every workspace in the lockfile must be present."
          end

          return unless (match = error_message.match(WORKSPACE_NOT_FOUND))

          raise Dependabot::DependencyFileNotResolvable,
                "package.json lists the workspace \"#{match[:path]}\", but it does not exist in the repository."
        end

        # The scheme, host and any non-default port of the URL, so the error names the registry and not a single
        # tarball. A registry on another port is a different endpoint.
        sig { params(url: String).returns(String) }
        def registry_origin(url)
          uri = URI.parse(url)
          default_port = T.cast(uri.default_port, T.nilable(Integer))
          port = ":#{uri.port}" if uri.port && uri.port != default_port
          "#{uri.scheme}://#{uri.host}#{port}"
        rescue URI::InvalidURIError
          url
        end

        # "@scope/name@1.2.3" and "name@1.2.3" both end in the version
        sig { params(spec: String).returns(String) }
        def package_name_from(spec)
          spec.sub(/@[^@]*\z/, "")
        end

        sig { void }
        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def npmrc_content(bun_lock)
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files,
            dependencies: lockfile_dependencies(bun_lock)
          ).npmrc_content
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_package_json_content(file)
          @updated_package_json_content ||= T.let({}, T.nilable(T::Hash[String, String]))
          @updated_package_json_content[file.name] ||=
            T.must(
              PackageJsonUpdater.new(
                package_json: file,
                dependencies: dependencies
              ).updated_package_json.content
            )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("package.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(String) }
        def base_dir
          T.must(dependency_files.first).directory
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end

        sig { params(message: String).returns(String) }
        def sanitize_message(message)
          message.gsub(/"|\[|\]|\}|\{/, "")
        end
      end
    end
  end
end
