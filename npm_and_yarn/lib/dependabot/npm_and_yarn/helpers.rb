# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module Helpers
      def self.npm_version(lockfile_content)
        "npm#{npm_version_numeric(lockfile_content)}"
      end

      def self.npm_version_numeric(lockfile_content)
        return 8 unless lockfile_content
        return 8 if JSON.parse(lockfile_content)["lockfileVersion"] >= 2

        6
      rescue JSON::ParserError
        6
      end

      # Run any number of yarn commands while ensuring that `enableScripts` is
      # set to false. Yarn commands should _not_ be ran outside of this helper
      # to ensure that postinstall scripts are never executed, as they could
      # contain malicious code.
      def self.run_yarn_commands(*commands)
        # We never want to execute postinstall scripts
        SharedHelpers.run_shell_command("yarn config set enableScripts false")
        commands.each { |cmd| SharedHelpers.run_shell_command(cmd) }
      end

      def self.dependencies_with_all_versions_metadata(dependency_set)
        working_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
        dependencies = []

        names = dependency_set.dependencies.map(&:name)
        names.each do |name|
          all_versions = dependency_set.all_versions_for_name(name, in_insertion_order: true)
          all_versions.each do |dep|
            metadata_versions = dep.metadata.fetch(:all_versions, [])
            if metadata_versions.any?
              metadata_versions.each { |a| working_set << a }
            else
              working_set << dep
            end
          end
          dependency = working_set.dependency_for_name(name)
          dependency.metadata[:all_versions] =
            working_set.all_versions_for_name(name, in_insertion_order: true)
          dependencies << dependency
        end

        dependencies
      end
    end
  end
end
