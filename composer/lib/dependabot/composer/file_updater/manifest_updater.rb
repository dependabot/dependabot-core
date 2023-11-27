# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/composer/file_parser"
require "dependabot/composer/file_updater"
require "dependabot/composer/version"
require "dependabot/composer/requirement"
require "dependabot/composer/native_helpers"
require "dependabot/composer/helpers"
require "dependabot/composer/update_checker/version_resolver"

module Dependabot
  module Composer
    class FileUpdater
      class ManifestUpdater
        class MissingExtensions < StandardError
          attr_reader :extensions

          def initialize(extensions)
            @extensions = extensions
            super
          end
        end

        def initialize(dependencies:, manifest:, credentials:)
          @dependencies = dependencies
          @manifest = manifest
          @credentials = credentials
        end

        def updated_manifest_content
          @updated_manifest_content ||= generate_updated_manifest_content
        rescue MissingExtensions => e
          previous_extensions = composer_platform_extensions.dup
          update_required_extensions(e.extensions)
          raise if previous_extensions == composer_platform_extensions

          retry
        end

        def generate_updated_manifest_content
          dependencies.reduce(manifest.content.dup) do |_content, dep|
            # Call the helper method for each dependency to update the composer.json
            updated_content = run_require_helper(dep).fetch("composer.json")
            raise "Expected content to change!" if composer_json == updated_content

            updated_content
          end
        end

        private

        attr_reader :dependencies, :dependency_files, :manifest, :credentials,
                    :composer_platform_extensions

        def run_require_helper(dependency)
          SharedHelpers.with_git_configured(credentials: credentials) do
            SharedHelpers.run_helper_subprocess(
              command: "php -d memory_limit=-1 #{php_helper_path}",
              allow_unsafe_shell_command: true,
              function: "require",
              env: credentials_env,
              args: [
                Dir.pwd,
                dependency.name,
                dependency.version,
                git_credentials,
                registry_credentials
              ]
            )
          end
        end

        def new_requirements(dependency)
          dependency.requirements.select { |r| r[:file] == manifest.name }
        end

        def old_requirement(dependency, new_requirement)
          dependency.previous_requirements
                    .select { |r| r[:file] == manifest.name }
                    .find { |r| r[:groups] == new_requirement[:groups] }
        end

        def updated_requirements(dependency)
          new_requirements(dependency)
            .reject { |r| dependency.previous_requirements.include?(r) }
        end

        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        def add_temporary_platform_extensions(content)
          json = JSON.parse(content)

          composer_platform_extensions.each do |extension, requirements|
            json["config"] ||= {}
            json["config"]["platform"] ||= {}
            json["config"]["platform"][extension] =
              version_for_reqs(requirements)
          end

          JSON.dump(json)
        end

        def lock_dependencies_being_updated(original_content)
          dependencies.reduce(original_content) do |content, dep|
            updated_req = dep.version
            next content unless Composer::Version.correct?(updated_req)

            old_req =
              dep.requirements.find { |r| r[:file] == "composer.json" }
                 &.fetch(:requirement)

            # When updating a subdep there won't be an old requirement
            next content unless old_req

            regex =
              /
                "#{Regexp.escape(dep.name)}"\s*:\s*
                "#{Regexp.escape(old_req)}"
              /x

            content.gsub(regex) do |declaration|
              declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
            end
          end
        end

        def lock_git_dependencies(content)
          json = JSON.parse(content)

          FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless json[keys[:manifest]]

            json[keys[:manifest]].each do |name, req|
              next unless req.start_with?("dev-")
              next if req.include?("#")

              commit_sha = parsed_lockfile
                           .fetch(keys[:lockfile], [])
                           .find { |d| d["name"] == name }
                           &.dig("source", "reference")
              updated_req_parts = req.split
              updated_req_parts[0] = updated_req_parts[0] + "##{commit_sha}"
              json[keys[:manifest]][name] = updated_req_parts.join(" ")
            end
          end

          JSON.dump(json)
        end

        def git_dependency_reference_error(error)
          ref = error.message.match(/checkout '(?<ref>.*?)'/)
                     .named_captures.fetch("ref")
          dependency_name =
            JSON.parse(lockfile.content)
                .values_at("packages", "packages-dev").flatten(1)
                .find { |dep| dep.dig("source", "reference") == ref }
                &.fetch("name")

          raise unless dependency_name

          raise GitDependencyReferenceNotFound, dependency_name
        end

        def post_process_lockfile(content)
          content = replace_patches(content)
          content = replace_content_hash(content)
          replace_platform_overrides(content)
        end

        def replace_patches(updated_content)
          content = updated_content
          %w(packages packages-dev).each do |package_type|
            JSON.parse(lockfile.content).fetch(package_type).each do |details|
              next unless details["extra"].is_a?(Hash)
              next unless (patches = details.dig("extra", "patches_applied"))

              updated_object = JSON.parse(content)
              updated_object_package =
                updated_object
                .fetch(package_type)
                .find { |d| d["name"] == details["name"] }

              next unless updated_object_package

              updated_object_package["extra"] ||= {}
              updated_object_package["extra"]["patches_applied"] = patches

              content =
                JSON.pretty_generate(updated_object, indent: "    ")
                    .gsub(/\[\n\n\s*\]/, "[]")
                    .gsub(/\}\z/, "}\n")
            end
          end
          content
        end

        def replace_content_hash(content)
          existing_hash = JSON.parse(content).fetch("content-hash")
          SharedHelpers.in_a_temporary_directory do
            File.write("composer.json", updated_composer_json_content)

            content_hash =
              SharedHelpers.run_helper_subprocess(
                command: "php #{php_helper_path}",
                function: "get_content_hash",
                env: credentials_env,
                args: [Dir.pwd]
              )

            content.gsub(existing_hash, content_hash)
          end
        end

        def replace_platform_overrides(content)
          original_object = JSON.parse(lockfile.content)
          original_overrides = original_object.fetch("platform-overrides", nil)

          updated_object = JSON.parse(content)

          if original_object.key?("platform-overrides")
            updated_object["platform-overrides"] = original_overrides
          else
            updated_object.delete("platform-overrides")
          end

          JSON.pretty_generate(updated_object, indent: "    ")
              .gsub(/\[\n\n\s*\]/, "[]")
              .gsub(/\}\z/, "}\n")
        end

        def version_for_reqs(requirements)
          req_arrays =
            requirements
            .map { |str| Composer::Requirement.requirements_array(str) }
          potential_versions =
            req_arrays.flatten.map do |req|
              op, version = req.requirements.first
              case op
              when ">" then version.bump
              when "<" then Composer::Version.new("0.0.1")
              else version
              end
            end

          version =
            potential_versions
            .find do |v|
              req_arrays.all? { |reqs| reqs.any? { |r| r.satisfied_by?(v) } }
            end
          raise "No matching version for #{requirements}!" unless version

          version.to_s
        end

        def update_required_extensions(additional_extensions)
          additional_extensions.each do |ext|
            composer_platform_extensions[ext.fetch(:name)] ||= []
            composer_platform_extensions[ext.fetch(:name)] +=
              [ext.fetch(:requirement)]
            composer_platform_extensions[ext.fetch(:name)] =
              composer_platform_extensions[ext.fetch(:name)].uniq
          end
        end

        def php_helper_path
          NativeHelpers.composer_helper_path(composer_version: composer_version)
        end

        def composer_version
          @composer_version ||= Helpers.composer_version(parsed_composer_json, parsed_lockfile)
        end

        def credentials_env
          credentials
            .select { |c| c.fetch("type") == "php_environment_variable" }
            .to_h { |cred| [cred["env-key"], cred.fetch("env-value", "-")] }
        end

        def git_credentials
          credentials
            .select { |cred| cred.fetch("type") == "git_source" }
            .select { |cred| cred["password"] }
        end

        def registry_credentials
          credentials
            .select { |cred| cred.fetch("type") == "composer_repository" }
            .select { |cred| cred["password"] }
        end

        def initial_platform
          platform_php = parsed_composer_json.dig("config", "platform", "php")

          platform = {}
          platform["php"] = [platform_php] if platform_php.is_a?(String) && requirement_valid?(platform_php)

          # NOTE: We *don't* include the require-dev PHP version in our initial
          # platform. If we fail to resolve with the PHP version specified in
          # `require` then it will be picked up in a subsequent iteration.
          requirement_php = parsed_composer_json.dig("require", "php")
          return platform unless requirement_php.is_a?(String)
          return platform unless requirement_valid?(requirement_php)

          platform["php"] ||= []
          platform["php"] << requirement_php
          platform
        end

        def requirement_valid?(req_string)
          Composer::Requirement.requirements_array(req_string)
          true
        rescue Gem::Requirement::BadRequirementError
          false
        end

        def parsed_composer_json
          @parsed_composer_json ||= JSON.parse(composer_json.content)
        end

        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(lockfile.content)
        end

        def composer_json
          @composer_json ||=
            dependency_files.find { |f| f.name == "composer.json" }
        end

        def lockfile
          @lockfile ||=
            dependency_files.find { |f| f.name == "composer.lock" }
        end

        def auth_json
          @auth_json ||= dependency_files.find { |f| f.name == "auth.json" }
        end

        def path_dependencies
          @path_dependencies ||=
            dependency_files.select { |f| f.name.end_with?("/composer.json") }
        end

        def write_temporary_dependency_files
          path_dependencies.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, file.content)
          end

          # TODO: Need to check if complete composer.json should be passed.
          File.write("composer.json", locked_composer_json_content)
          File.write("composer.lock", lockfile.content)
          File.write("auth.json", auth_json.content) if auth_json
        end

        def locked_composer_json_content
          content = parsed_composer_json
          content = lock_dependencies_being_updated(content)
          content = lock_git_dependencies(content) if @lock_git_deps != false
          content = add_temporary_platform_extensions(content)
          content
        end
      end
    end
  end
end
