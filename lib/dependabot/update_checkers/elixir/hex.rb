# frozen_string_literal: true

require "excon"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

require "json"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex < Dependabot::UpdateCheckers::Base
        require_relative "hex/version"
        require_relative "hex/requirements_updater"

        def latest_version
          return latest_version_for_git_dependency if git_dependency?
          return latest_resolvable_version unless hex_registry_response

          latest_release_on_hex_registry
        end

        def latest_resolvable_version
          @latest_resolvable_version ||=
            if git_dependency?
              latest_resolvable_version_for_git_dependency
            else
              fetch_latest_resolvable_version(unlock_requirement: true)
            end
        end

        def latest_resolvable_version_with_no_unlock
          if git_dependency? && git_commit_checker.pinned?
            return dependency.version
          end

          @latest_resolvable_version_with_no_unlock ||=
            fetch_latest_resolvable_version(unlock_requirement: false)
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
        end

        def version_class
          Hex::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Elixir (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_version_for_git_dependency
          latest_git_version_sha
        end

        def latest_resolvable_version_for_git_dependency
          # TODO: we should be updating the ref here if pinned to a
          # version-like ref. For now, this setup means we at least get
          # branch updates, though.
          fetch_latest_resolvable_version(unlock_requirement: false)
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def latest_git_version_sha
          # If the gem isn't pinned, the latest version is just the latest
          # commit for the specified branch.
          unless git_commit_checker.pinned?
            return git_commit_checker.head_commit_for_current_branch
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will then be the SHA
          # of the latest tag that looks like a version.
          if git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return latest_tag&.fetch(:tag_sha) || dependency.version
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          dependency.version
        end

        def fetch_latest_resolvable_version(unlock_requirement:)
          latest_resolvable_version =
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files(
                unlock_requirement: unlock_requirement
              )
              FileUtils.cp(elixir_helper_check_update_path, "check_update.exs")

              SharedHelpers.run_helper_subprocess(
                env: mix_env,
                command: "mix run #{elixir_helper_path}",
                function: "get_latest_resolvable_version",
                args: [Dir.pwd, dependency.name]
              )
            end

          return if latest_resolvable_version.nil?
          if latest_resolvable_version.match?(/^[0-9a-f]{40}$/)
            return latest_resolvable_version
          end
          version_class.new(latest_resolvable_version)
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_hex_errors(error)
        end

        def handle_hex_errors(error)
          if git_dependency? && error.message.include?("resolution failed")
            return nil
          end
          if error.message.start_with?("Invalid requirement")
            raise Dependabot::DependencyFileNotResolvable, error.message
          end
          raise error
        end

        def write_temporary_dependency_files(unlock_requirement:)
          mixfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(
              path,
              prepare_mixfile(file, unlock_requirement: unlock_requirement)
            )
          end
          File.write("mix.lock", lockfile.content)
        end

        def prepare_mixfile(file, unlock_requirement:)
          content = file.content
          if unlock_requirement && dependency_appears_in_file?(file.name)
            content = relax_version(content, filename: file.name)
          end
          sanitize_mixfile(content)
        end

        def relax_version(content, filename:)
          old_requirement =
            dependency.requirements.find { |r| r.fetch(:file) == filename }.
            fetch(:requirement)

          return content unless old_requirement

          new_requirement =
            if dependency.version
              ">= #{dependency.version}"
            elsif wants_prerelease?
              ">= 0.0.1-rc1"
            else
              ">= 0"
            end

          requirement_line_regex =
            /
              :#{Regexp.escape(dependency.name)},.*
              #{Regexp.escape(old_requirement)}
            /x

          content.gsub(requirement_line_regex) do |requirement_line|
            requirement_line.gsub(old_requirement, new_requirement)
          end
        end

        def sanitize_mixfile(content)
          content.
            gsub(/File\.read!\(.*?\)/, '"0.0.1"').
            gsub(/File\.read\(.*?\)/, '{:ok, "0.0.1"}')
        end

        def mix_env
          {
            "MIX_EXS" => File.join(project_root, "helpers/elixir/mix.exs"),
            "MIX_LOCK" => File.join(project_root, "helpers/elixir/mix.lock"),
            "MIX_DEPS" => File.join(project_root, "helpers/elixir/deps"),
            "MIX_QUIET" => "1"
          }
        end

        def elixir_helper_path
          File.join(project_root, "helpers/elixir/bin/run.exs")
        end

        def elixir_helper_check_update_path
          File.join(project_root, "helpers/elixir/bin/check_update.exs")
        end

        def mixfiles
          mixfiles = dependency_files.select { |f| f.name.end_with?("mix.exs") }
          raise "No mix.exs!" unless mixfiles.any?
          mixfiles
        end

        def lockfile
          lockfile = dependency_files.find { |f| f.name == "mix.lock" }
          raise "No mix.lock!" unless lockfile
          lockfile
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
        end

        def dependency_appears_in_file?(file_name)
          dependency.requirements.any? { |r| r[:file] == file_name }
        end

        def latest_release_on_hex_registry
          versions =
            hex_registry_response["releases"].
            select { |release| version_class.correct?(release["version"]) }.
            map { |release| version_class.new(release["version"]) }

          versions = versions.reject(&:prerelease?) unless wants_prerelease?
          versions.sort.last
        end

        def hex_registry_response
          return @hex_registry_response unless @hex_registry_response.nil?

          response = Excon.get(
            dependency_url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          return nil unless response.status == 200

          @hex_registry_response = JSON.parse(response.body)
        end

        def wants_prerelease?
          current_version = dependency.version
          if current_version &&
             version_class.correct?(current_version) &&
             version_class.new(current_version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z0-9]/)
          end
        end

        def dependency_url
          "https://hex.pm/api/packages/#{dependency.name}"
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              github_access_token: github_access_token
            )
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
