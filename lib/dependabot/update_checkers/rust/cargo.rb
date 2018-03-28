# frozen_string_literal: true

require "excon"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo < Dependabot::UpdateCheckers::Base
        require_relative "cargo/requirements_updater"
        require_relative "cargo/requirement"
        require_relative "cargo/version"

        def latest_version
          # TODO: Handle git dependencies
          return if git_dependency?
          return if path_dependency?

          @latest_version =
            begin
              versions = available_versions
              versions.reject!(&:prerelease?) unless wants_prerelease?
              versions.sort.last
            end
        end

        def latest_resolvable_version
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # TODO: Handle git dependencies
          return if git_dependency?
          return if path_dependency?

          @latest_resolvable_version_with_no_unlock ||=
            begin
              versions = available_versions
              reqs = dependency.requirements.map do |r|
                Cargo::Requirement.new(r.fetch(:requirement).split(","))
              end
              versions.reject!(&:prerelease?) unless wants_prerelease?
              versions.select! { |v| reqs.all? { |r| r.satisfied_by?(v) } }
              versions.sort.last
            end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            library: dependency.version.nil?
          ).updated_requirements
        end

        def version_class
          Cargo::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Rust (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def wants_prerelease?
          if dependency.version &&
             Cargo::Version.new(dependency.version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        def available_versions
          crates_listing.
            fetch("versions", []).
            reject { |v| v["yanked"] }.
            map { |v| Cargo::Version.new(v.fetch("num")) }
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def path_dependency?
          sources = dependency.requirements.
                    map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1
          sources.first&.fetch(:type) == "path"
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

        def crates_listing
          return @crates_listing unless @crates_listing.nil?

          response = Excon.get(
            "https://crates.io/api/v1/crates/#{dependency.name}",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @crates_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
