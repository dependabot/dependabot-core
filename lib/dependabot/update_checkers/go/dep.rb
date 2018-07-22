# frozen_string_literal: true

require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Go
      class Dep < Dependabot::UpdateCheckers::Base
        require_relative "dep/latest_version_finder"

        def latest_version
          @latest_version ||=
            LatestVersionFinder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions
            ).latest_version
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
