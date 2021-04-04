# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "open3"
require "yaml"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/git_commit_checker"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/pub/native_helpers"

module Dependabot
  module Pub
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_TYPES =
        %w(dependencies dev_dependencies).freeze

      def parse
        dependency_set = DependencySet.new
        dependency_set += pubspec_yaml_dependencies
        dependency_set += pubspec_lock_dependencies
        dependency_set.dependencies
      end

      private

      def pubspec_yaml_dependencies
        dependency_set = DependencySet.new

        pubspec_yaml_files.each do |file|
          DEPENDENCY_TYPES.each do |type|
            deps = YAML.load(file.content)[type] || {}
            deps.each do |name, requirement|
              dep = build_dependency(
                file: file, type: type, name: name, requirement: requirement
              )
              next unless dep

              dependency_set << dep if dep
            end
          end
        end

        dependency_set
      end

      def pubspec_lock_dependencies
        dependency_set = DependencySet.new

        pubspec_lock_files.each do |file|
          lock_file_packages(file).each do |name, details|
            dependency_set << Dependency.new(
              name: name,
              version: details["version"],
              package_manager: "pub",
              requirements: []
            )
          end
        end

        dependency_set
      end

      def build_dependency(file:, type:, name:, requirement:)
        version = version_for(name: name, manifest_name: file.name)
        req = requirement_for(requirement)
        return nil unless req

        Dependency.new(
          name: name,
          version: version,
          package_manager: "pub",
          requirements: [{
            requirement: req,
            file: file.name,
            groups: [type],
            source: source_for(name: name, manifest_name: file.name)
          }]
        )
      end

      def requirement_for(requirement)
        return requirement if requirement.is_a?(String)

        if requirement.is_a?(Hash) && requirement.key?("git")
          git = requirement["git"]

          return "#{git}" if git.is_a?(String)

          url = git["url"]

          return url
        end

        nil
      end

      def version_for(name:, manifest_name:)
        version = lockfile_details(
          name: name,
          manifest_name: manifest_name
        )&.fetch("version", nil)
        version
      end

      def source_for(name:, manifest_name:)
        details = lockfile_details(
          name: name,
          manifest_name: manifest_name
        )
        source_type = details["source"]
        description = details["description"] || {}

        if source_type == "hosted"
          return {
            type: source_type,
            url: description["url"]
          }
        end
        if source_type == "git"
          return {
            type: source_type,
            url: description["url"],
            path: description["path"],
            branch: nil,
            ref: description["ref"],
            resolved_ref: description["resolved-ref"]
          }
        end
        if source_type == "path"
          return {
            type: source_type,
            path: description["path"],
            relative: description["relative"]
          }
        end

        nil
      end

      def lockfile_details(name:, manifest_name:)
        lock_file_name = lockfile_name_for(manifest_name)
        packages = lock_file_packages(lock_file_name)
        dep = packages[name] || {}
        dep
      end

      def lockfile_name_for(manifest_filename)
        dir_name = File.dirname(manifest_filename)
        lock_file = Pathname.new(File.join(dir_name, "pubspec.lock")).cleanpath.to_path

        pubspec_lock_files.find { |f| f.name == lock_file }
      end

      def lock_file_packages(file)
        YAML.load(file.content)["packages"] || {}
      end

      def pubspec_yaml_files
        dependency_files.select { |f| f.name.end_with?("pubspec.yaml") }
      end

      def pubspec_lock_files
        dependency_files.select { |f| f.name.end_with?("pubspec.lock") }
      end

      def check_required_files
        raise "No pubspec.yaml!" unless get_original_file("pubspec.yaml")
      end
    end
  end
end

Dependabot::FileParsers.
  register("pub", Dependabot::Pub::FileParser)
