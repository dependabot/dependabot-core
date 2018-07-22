# frozen_string_literal: true

require "toml-rb"

require "dependabot/source"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Go
      class Dep < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||=
            if git_dependency? then latest_version_for_git_dependency
            else latest_release_tag_version
            end
        end

        def latest_resolvable_version
          # Resolving the dependency files to get the latest version of
          # this dependency that doesn't cause conflicts is hard, and needs to
          # be done through a language helper that piggy-backs off of the
          # package manager's own resolution logic (see PHP, for example).
        end

        def latest_resolvable_version_with_no_unlock
          # Will need the same resolution logic as above, just without the
          # file unlocking.
        end

        def updated_requirements
          # If the dependency file needs to be updated we store the updated
          # requirements on the dependency.
          dependency.requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Go (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_release_tag_version
          if @latest_release_tag_lookup_attempted
            return @latest_release_tag_version
          end

          @latest_release_tag_lookup_attempted = true

          latest_release_version_str = fetch_latest_release_tag&.sub(/^v?/, "")
          return unless latest_release_version_str
          return unless version_class.correct?(latest_release_version_str)

          @latest_release_tag_version =
            version_class.new(latest_release_version_str)
        end

        def fetch_latest_release_tag
          # If this is a git dependency then getting the latest tag is trivial
          if git_dependency?
            return git_commit_checker.local_tag_for_latest_version&.fetch(:tag)
          end

          # If not, we need to find the URL for the source code.
          path = dependency.requirements.
                 map { |r| r.dig(:source, :source) }.
                 compact.first
          return unless path

          updated_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")
          # Currently, Dependabot::Source.new will return `nil` if it can't find
          # a git SCH associated with a path. If it is ever extended to handle
          # non-git sources we'll need to add an additional check here.
          source = Source.from_url(updated_path)
          return unless source

          # Given a source, we want to find the latest tag. Piggy-back off the
          # logic in GitCommitChecker to do so.
          git_dep = Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirements: [{
              file: "Gopkg.toml",
              groups: [],
              requirement: nil,
              source: { type: "git", url: source.url }
            }],
            package_manager: dependency.package_manager
          )

          GitCommitChecker.
            new(dependency: git_dep, credentials: credentials).
            local_tag_for_latest_version&.fetch(:tag)
        end

        def latest_version_for_git_dependency
          latest_release = latest_release_tag_version

          # If there's been a release that includes the current pinned ref or
          # that the current branch is behind, we switch to that release.
          return latest_release if git_branch_or_ref_in_release?(latest_release)

          # Otherwise, if the gem isn't pinned, the latest version is just the
          # latest commit for the specified branch.
          unless git_commit_checker.pinned?
            return git_commit_checker.head_commit_for_current_branch
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will be the tag name
          # (NOT the tag SHA, unlike in other package managers).
          if git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return latest_tag&.fetch(:tag)
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          nil
        end

        def git_branch_or_ref_in_release?(release)
          return false unless release
          git_commit_checker.branch_or_ref_in_release?(release)
        end

        def dependencies_to_import
          # There's no way to tell whether dependencies that appear in the
          # lockfile are there because they're imported themselves or because
          # they're sub-dependencies of something else. v0.5.0 will fix that
          # problem, but for now we just have to import everything.
          #
          # NOTE: This means the `inputs-digest` we generate will be wrong.
          # That's a pity, but we'd have to iterate through too many
          # possibilities to get it right. Again, this is fixed in v0.5.0.
          parsed_file(lockfile).fetch("required").map do |detail|
            detail["name"]
          end
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials
            )
        end

        def parsed_file(file)
          @parsed_file ||= {}
          @parsed_file[file.name] ||= TomlRB.parse(file.content)
        rescue TomlRB::ParseError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        def manifest
          @manifest ||= dependency_files.find { |f| f.name == "Gopkg.toml" }
          raise "No Gopkg.lock!" unless @manifest
          @manifest
        end

        def lockfile
          @lockfile = dependency_files.find { |f| f.name == "Gopkg.lock" }
          raise "No Gopkg.lock!" unless @lockfile
          @lockfile
        end
      end
    end
  end
end
