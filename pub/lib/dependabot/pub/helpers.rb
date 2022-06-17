# frozen_string_literal: true

require "json"
require "open3"
require "digest"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/pub/requirement"

module Dependabot
  module Pub
    module Helpers
      def self.pub_helpers_path
        File.join(ENV["DEPENDABOT_NATIVE_HELPERS_PATH"], "pub")
      end

      def self.run_infer_sdk_versions(url: nil)
        stdout, _, status = Open3.capture3(
          {},
          File.join(pub_helpers_path, "infer_sdk_versions"),
          *("--flutter-releases-url=#{url}" if url)
        )
        return nil unless status.success?

        JSON.parse(stdout)
      end

      private

      def dependency_services_list
        JSON.parse(run_dependency_services("list"))["dependencies"]
      end

      def dependency_services_report
        sha256 = Digest::SHA256.new
        dependency_files.each do |f|
          sha256 << f.path + "\n" + f.content + "\n"
        end
        hash = sha256.hexdigest

        cache_file = "/tmp/report-#{hash}-pid-#{Process.pid}.json"
        return JSON.parse(File.read(cache_file)) if File.file?(cache_file)

        report = JSON.parse(run_dependency_services("report"))["dependencies"]
        File.write(cache_file, JSON.generate(report))
        report
      end

      def dependency_services_apply(dependency_changes)
        run_dependency_services("apply", stdin_data: dependencies_to_json(dependency_changes)) do
          dependency_files.map do |f|
            updated_file = f.dup
            updated_file.content = File.read(f.name)
            updated_file
          end
        end
      end

      # Clones the flutter repo into /tmp/flutter if needed
      def ensure_flutter_repo
        return if File.directory?("/tmp/flutter/.git")

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
      def check_out_flutter_ref(ref)
        ensure_flutter_repo
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
      def ensure_right_flutter_release
        @ensure_right_flutter_release ||= begin
          versions = Helpers.run_infer_sdk_versions url: options[:flutter_releases_url]
          flutter_ref = if versions
                          "refs/tags/#{versions['flutter']}"
                        else
                          # Choose the 'stable' version if the tool failed to infer a version.
                          "stable"
                        end

          check_out_flutter_ref flutter_ref

          # Run `flutter --version` to make Flutter download engine artifacts and create flutter/version.
          _, stderr, status = Open3.capture3(
            {},
            "/tmp/flutter/bin/flutter",
            "doctor",
            chdir: "/tmp/flutter/"
          )
          raise Dependabot::DependabotError, "Running 'flutter doctor' failed: #{stderr}" unless status.success?

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

          parsed = JSON.parse(stdout)
          {
            "flutter" => parsed["frameworkVersion"],
            "dart" => parsed["dartSdkVersion"]
          }
        end
      end

      def run_dependency_services(command, stdin_data: nil)
        SharedHelpers.in_a_temporary_directory do
          dependency_files.each do |f|
            in_path_name = File.join(Dir.pwd, f.directory, f.name)
            FileUtils.mkdir_p File.dirname(in_path_name)
            File.write(in_path_name, f.content)
          end
          sdk_versions = ensure_right_flutter_release
          SharedHelpers.with_git_configured(credentials: credentials) do
            env = {
              "CI" => "true",
              "PUB_ENVIRONMENT" => "dependabot",
              "FLUTTER_ROOT" => "/tmp/flutter",
              "PUB_HOSTED_URL" => options[:pub_hosted_url],
              # This variable will make the solver run assuming that Dart SDK version.
              # TODO(sigurdm): Would be nice to have a better handle for fixing the dart sdk version.
              "_PUB_TEST_SDK_VERSION" => sdk_versions["dart"]
            }
            Dir.chdir File.join(Dir.pwd, dependency_files.first.directory) do
              stdout, stderr, status = Open3.capture3(
                env.compact,
                File.join(Helpers.pub_helpers_path, "dependency_services"),
                command,
                stdin_data: stdin_data
              )
              raise Dependabot::DependabotError, "dependency_services failed: #{stderr}" unless status.success?
              return stdout unless block_given?

              yield
            end
          end
        end
      end

      # Parses a dependency as listed by `dependency_services list`.
      def parse_listed_dependency(json)
        params = {
          name: json["name"],
          version: json["version"],
          package_manager: "pub",
          requirements: []
        }

        if json["kind"] != "transitive" && !json["constraint"].nil?
          constraint = json["constraint"]
          params[:requirements] << {
            requirement: constraint,
            groups: [json["kind"]],
            source: json["source"],
            file: "pubspec.yaml"
          }
        end
        Dependency.new(**params)
      end

      # Parses the updated dependencies returned by
      # `dependency_services report`.
      #
      # The `requirements_update_strategy`` is
      # used to chose the right updated constraint.
      def parse_updated_dependency(json, requirements_update_strategy: nil)
        params = {
          name: json["name"],
          version: json["version"],
          package_manager: "pub",
          requirements: []
        }
        constraint_field = constraint_field_from_update_strategy(requirements_update_strategy)

        if json["kind"] != "transitive" && !json[constraint_field].nil?
          constraint = json[constraint_field]
          params[:requirements] << {
            requirement: constraint,
            groups: [json["kind"]],
            source: nil, # TODO: Expose some information about the source
            file: "pubspec.yaml"
          }
        end

        if json["previousVersion"]
          params = {
            **params,
            previous_version: json["previousVersion"],
            previous_requirements: []
          }
          if json["kind"] != "transitive" && !json["previousConstraint"].nil?
            constraint = json["previousConstraint"]
            params[:previous_requirements] << {
              requirement: constraint,
              groups: [json["kind"]],
              source: nil, # TODO: Expose some information about the source
              file: "pubspec.yaml"
            }
          end
        end
        Dependency.new(**params)
      end

      # expects "auto" to already have been resolved to one of the other
      # strategies.
      def constraint_field_from_update_strategy(requirements_update_strategy)
        case requirements_update_strategy
        when "widen_ranges"
          "constraintWidened"
        when "bump_versions"
          "constraintBumped"
        when "bump_versions_if_necessary"
          "constraintBumpedIfNeeded"
        end
      end

      def dependencies_to_json(dependencies)
        if dependencies.nil?
          nil
        else
          deps = dependencies.map do |d|
            source = d.requirements.empty? ? nil : d.requirements.first[:source]
            obj = {
              "name" => d.name,
              "version" => d.version,
              "source" => source
            }

            obj["constraint"] = d.requirements[0][:requirement].to_s unless d.requirements.nil? || d.requirements.empty?
            obj
          end
          JSON.generate({
            "dependencyChanges" => deps
          })
        end
      end
    end
  end
end
