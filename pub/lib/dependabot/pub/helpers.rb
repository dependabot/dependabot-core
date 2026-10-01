# typed: strong
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/logger"
require "dependabot/pub/dependency_services_result"
require "dependabot/pub/package/registry_package"
require "dependabot/pub/requirement"
require "dependabot/pub/requirement_source"
require "dependabot/requirements_update_strategy"
require "dependabot/shared_helpers"

module Dependabot
  module Pub
    module Helpers
      include Kernel

      extend T::Sig
      extend T::Helpers

      abstract!

      class SdkVersions < T::ImmutableStruct
        const :flutter, String
        const :dart, String
        const :channel, T.nilable(String), default: nil
      end

      sig { abstract.returns(T::Array[Dependabot::Credential]) }
      def credentials; end

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def dependency_files; end

      sig { abstract.returns(T::Hash[Symbol, T.anything]) }
      def options; end

      sig { returns(String) }
      def self.pub_helpers_path
        File.join(ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil), "pub")
      end

      sig do
        params(
          dir: T.any(Pathname, String),
          url: T.nilable(String)
        )
          .returns(T.nilable(SdkVersions))
      end
      def self.run_infer_sdk_versions(dir, url: nil)
        env = {}
        cmd = File.join(pub_helpers_path, "infer_sdk_versions")
        opts = url ? "--flutter-releases-url=#{url}" : ""
        stdout, _, status = Open3.capture3(env, cmd, opts, chdir: dir)
        return nil unless status.success?

        fields = JsonValueParser.object(JsonValueParser.parse(stdout, "infer_sdk_versions"), "infer_sdk_versions")
        SdkVersions.new(
          flutter: JsonValueParser.string(fields["flutter"], "infer_sdk_versions.flutter"),
          dart: JsonValueParser.string(fields["dart"], "infer_sdk_versions.dart"),
          channel: JsonValueParser.string(fields["channel"], "infer_sdk_versions.channel")
        )
      rescue JsonValueParser::InvalidValue => e
        DependencyServicesResult.invalid_result("infer_sdk_versions", e.message)
      end

      private

      sig { returns(T::Array[DependencyServicesResult::ListedDependency]) }
      def dependency_services_list
        DependencyServicesResult.list_from_json(run_dependency_services("list"))
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def repository_url(dependency)
        repository_url = RequirementSource.new(dependency.requirements.first).description_string("url") ||
                         option_string(:pub_hosted_url) || "https://pub.dev"
        repository_url.delete_suffix("/")
      end

      sig { params(dependency: Dependabot::Dependency).returns(Package::RegistryPackage) }
      def fetch_package_listing(dependency)
        # Because we get the security_advisories as a set of constraints, we
        # fetch the list of all versions and filter them to a list of vulnerable
        # versions.
        #
        # Ideally we would like the helper to be the only one doing requests to
        # the repository. But this should work for now:
        response = Dependabot::RegistryClient.get(url: "#{repository_url(dependency)}/api/packages/#{dependency.name}")
        Package::RegistryPackage.from_json(response.body)
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::Pub::Version]) }
      def available_versions(dependency)
        fetch_package_listing(dependency).versions
      end

      sig { returns(T::Array[DependencyServicesResult::ReportEntry]) }
      def dependency_services_report
        sha256 = Digest::SHA256.new
        dependency_files.each do |f|
          sha256 << (f.path + "\n" + T.must(f.content) + "\n")
        end
        hash = sha256.hexdigest

        cache_file = "/tmp/report-#{hash}-pid-#{Process.pid}.json"
        return DependencyServicesResult.report_from_cache(File.read(cache_file)).dependencies if File.file?(cache_file)

        report = DependencyServicesResult.report_from_json(run_dependency_services("report"))
        File.write(cache_file, report.cache_content)
        report.dependencies
      end

      sig do
        params(
          dependency_changes: T.nilable(T::Array[Dependabot::Dependency])
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def dependency_services_apply(dependency_changes)
        T.cast(
          run_dependency_services("apply", stdin_data: dependencies_to_json(dependency_changes)) do |temp_dir|
            dependency_files.map do |f|
              updated_file = f.dup
              updated_file.content = File.read(File.join(temp_dir, f.name))
              updated_file
            end
          end,
          T::Array[Dependabot::DependencyFile]
        )
      end

      sig { params(dependency: Dependabot::Dependency).returns(Excon::Response) }
      def fetch_package_metadata(dependency)
        Dependabot::RegistryClient.get(url: "#{repository_url(dependency)}/api/packages/#{dependency.name}")
      end

      # Clones the flutter repo into /tmp/flutter if needed
      sig { void }
      def ensure_flutter_repo
        return if File.directory?("/tmp/flutter/.git")

        Dependabot.logger.info "Cloning the flutter repo https://github.com/flutter/flutter."
        # Make a flutter checkout
        _, stderr, status = Open3.capture3(
          {},
          "git",
          "clone",
          "--no-checkout",
          "https://github.com/flutter/flutter",
          chdir: "/tmp/"
        )
        raise Dependabot::DependabotError, "Cloning Flutter failed: #{stderr}" unless status.success?
      end

      # Will ensure that /tmp/flutter contains the flutter repo checked out at `ref`.
      sig { params(ref: String).void }
      def check_out_flutter_ref(ref)
        ensure_flutter_repo
        Dependabot.logger.info "Checking out Flutter version #{ref}"
        # Ensure we have the right version (by tag)
        _, stderr, status = Open3.capture3(
          {},
          "git",
          "fetch",
          "origin",
          ref,
          chdir: "/tmp/flutter"
        )
        raise Dependabot::DependabotError, "Fetching Flutter version #{ref} failed: #{stderr}" unless status.success?

        # Check out the right version in git.
        _, stderr, status = Open3.capture3(
          {},
          "git",
          "checkout",
          ref,
          chdir: "/tmp/flutter"
        )
        return if status.success?

        raise Dependabot::DependabotError, "Checking out flutter #{ref} failed: #{stderr}"
      end

      ## Detects the right flutter release to use for the pubspec.yaml.
      ## Then checks it out if it is not already.
      ## Returns the sdk versions
      sig { params(dir: T.any(Pathname, String)).returns(SdkVersions) }
      def ensure_right_flutter_release(dir)
        versions = Helpers.run_infer_sdk_versions(
          File.join(dir, T.must(dependency_files.first).directory),
          url: option_string(:flutter_releases_url)
        )
        flutter_ref =
          if versions
            Dependabot.logger.info(
              "Installing the Flutter SDK version: #{versions.flutter} " \
              "from channel #{versions.channel} with Dart #{versions.dart}"
            )
            "refs/tags/#{versions.flutter}"
          else
            Dependabot.logger.info(
              "Failed to infer the flutter version. Attempting to use latest stable release."
            )
            # Choose the 'stable' version if the tool failed to infer a version.
            "stable"
          end

        check_out_flutter_ref flutter_ref
        run_flutter_doctor
        run_flutter_version
      end

      sig { void }
      def run_flutter_doctor
        Dependabot.logger.info(
          "Running `flutter doctor` to install artifacts and create flutter/version."
        )
        _, stderr, status = Open3.capture3(
          {},
          "/tmp/flutter/bin/flutter",
          "doctor",
          chdir: "/tmp/flutter/"
        )
        raise Dependabot::DependabotError, "Running 'flutter doctor' failed: #{stderr}" unless status.success?
      end

      # Runs `flutter version` and returns the dart and flutter version numbers in a map.
      sig { returns(SdkVersions) }
      def run_flutter_version
        Dependabot.logger.info "Running `flutter --version`"
        # Run `flutter --version --machine` to get the current flutter version.
        stdout, stderr, status = Open3.capture3(
          {},
          "/tmp/flutter/bin/flutter",
          "--version",
          "--machine",
          chdir: "/tmp/flutter/"
        )
        unless status.success?
          raise Dependabot::DependabotError,
                "Running 'flutter --version --machine' failed: #{stderr}"
        end

        context = "flutter --version"
        parsed = JsonValueParser.object(JsonValueParser.parse(stdout, context), context)
        flutter_version = JsonValueParser.string(parsed["frameworkVersion"], "#{context}.frameworkVersion")
        dart_version = JsonValueParser.string(parsed["dartSdkVersion"], "#{context}.dartSdkVersion").split.first
        raise JsonValueParser::InvalidValue, "#{context}.dartSdkVersion must contain a version" unless dart_version

        Dependabot.logger.info(
          "Installed the Flutter SDK version: #{flutter_version} with Dart #{dart_version}."
        )
        SdkVersions.new(flutter: flutter_version, dart: dart_version)
      rescue JsonValueParser::InvalidValue => e
        DependencyServicesResult.invalid_result("flutter --version", e.message)
      end

      sig do
        type_parameters(:T)
          .params(
            command: String,
            stdin_data: T.nilable(String),
            blk: T.nilable(T.proc.params(arg0: String).returns(T.type_parameter(:T)))
          )
          .returns(T.any(String, T.type_parameter(:T)))
      end
      def run_dependency_services(command, stdin_data: nil, &blk)
        SharedHelpers.in_a_temporary_directory do |temp_dir|
          dependency_files.each do |f|
            in_path_name = File.join(temp_dir, f.directory, f.name)
            FileUtils.mkdir_p File.dirname(in_path_name)
            File.write(in_path_name, f.content)
          end
          sdk_versions = ensure_right_flutter_release(temp_dir)
          SharedHelpers.with_git_configured(credentials: credentials) do
            env = {
              "CI" => "true",
              "PUB_ENVIRONMENT" => "dependabot",
              "FLUTTER_ROOT" => "/tmp/flutter",
              "DART_ROOT" => "/tmp/flutter/bin/cache/dart-sdk",
              "PUB_HOSTED_URL" => option_string(:pub_hosted_url),
              # This variable will make the solver run assuming that Dart SDK version.
              # TODO(sigurdm): Would be nice to have a better handle for fixing the dart sdk version.
              "_PUB_TEST_SDK_VERSION" => sdk_versions.dart
            }
            command_dir = File.join(temp_dir, T.must(dependency_files.first).directory)

            stdout, stderr, status = Open3.capture3(
              env.compact,
              File.join(Helpers.pub_helpers_path, "dependency_services"),
              command,
              stdin_data: stdin_data,
              chdir: command_dir
            )
            raise_error(stderr) unless status.success?
            return stdout unless blk

            yield command_dir
          end
        end
      end

      sig { params(stderr: String).returns(T.noreturn) }
      def raise_error(stderr)
        if stderr.match?(/Failed parsing lock file|Unsupported operation|Duplicate mapping key|"name" field/)
          raise DependencyFileNotEvaluatable, "dependency_services failed: #{stderr}"
        elsif stderr.include?("Git error")
          raise Dependabot::InvalidGitAuthToken, "dependency_services failed: #{stderr}"
        elsif stderr.match?(/version solving failed|found no workspace root|Only apply dependency_services to the root/)
          raise Dependabot::DependencyFileNotResolvable, "dependency_services failed: #{stderr}"
        elsif stderr.include?("Could not find a file named \"pubspec.yaml\"")
          raise Dependabot::DependencyFileNotFound.new("pubspec.yaml", "dependency_services failed: #{stderr}")
        else
          raise Dependabot::DependabotError, "dependency_services failed: #{stderr}"
        end
      end

      # Parses a dependency as listed by `dependency_services list`.
      sig { params(entry: DependencyServicesResult::ListedDependency).returns(Dependabot::Dependency) }
      def parse_listed_dependency(entry)
        requirements = []

        if entry.kind != "transitive" && !entry.constraint.nil?
          requirements << {
            requirement: entry.constraint,
            groups: [entry.kind],
            source: entry.source,
            file: "pubspec.yaml"
          }
        end
        Dependency.new(name: entry.name, version: entry.version, package_manager: "pub", requirements: requirements)
      end

      # Parses the updated dependencies returned by
      # `dependency_services report`.
      #
      # The `requirements_update_strategy`` is
      # used to chose the right updated constraint.
      sig do
        params(
          entry: DependencyServicesResult::DependencyUpdate,
          requirements_update_strategy: Dependabot::RequirementsUpdateStrategy
        )
          .returns(Dependabot::Dependency)
      end
      def parse_updated_dependency(entry, requirements_update_strategy)
        requirements = []
        constraint = constraint_from_update_strategy(entry, requirements_update_strategy)

        if entry.kind != "transitive" && !constraint.nil?
          requirements << {
            requirement: constraint,
            groups: [entry.kind],
            source: nil, # TODO: Expose some information about the source
            file: "pubspec.yaml"
          }
        end

        previous_requirements = []
        if entry.previous_version && entry.kind != "transitive" && !entry.previous_constraint.nil?
          previous_requirements << {
            requirement: entry.previous_constraint,
            groups: [entry.kind],
            source: nil, # TODO: Expose some information about the source
            file: "pubspec.yaml"
          }
        end

        Dependency.new(
          name: entry.name,
          version: entry.version,
          package_manager: "pub",
          requirements: requirements,
          previous_version: entry.previous_version,
          previous_requirements: entry.previous_version ? previous_requirements : nil
        )
      end

      # expects "auto" to already have been resolved to one of the other
      # strategies.
      sig do
        params(
          entry: DependencyServicesResult::DependencyUpdate,
          requirements_update_strategy: Dependabot::RequirementsUpdateStrategy
        )
          .returns(T.nilable(String))
      end
      def constraint_from_update_strategy(entry, requirements_update_strategy)
        case requirements_update_strategy
        when RequirementsUpdateStrategy::WidenRanges
          entry.constraint_widened
        when RequirementsUpdateStrategy::BumpVersions
          entry.constraint_bumped
        when RequirementsUpdateStrategy::BumpVersionsIfNecessary
          entry.constraint_bumped_if_needed
        else
          raise "Unexpected requirements_update_strategy #{requirements_update_strategy}"
        end
      end

      sig { params(key: Symbol).returns(T.nilable(String)) }
      def option_string(key)
        value = options[key]
        return unless value

        case value
        when String then value
        else raise TypeError, "Pub option #{key} must be a string or nil"
        end
      end

      sig do
        params(
          dependencies: T.nilable(T::Array[Dependabot::Dependency])
        )
          .returns(T.nilable(String))
      end
      def dependencies_to_json(dependencies)
        return if dependencies.nil?

        changes = dependencies.map do |dependency|
          requirement = dependency.requirements.first
          fields = {
            "name" => dependency.name,
            "version" => dependency.version,
            "source" => requirement&.source
          }
          fields["constraint"] = requirement.requirement.to_s if requirement
          fields
        end
        JSON.generate("dependencyChanges" => changes)
      end
    end
  end
end
