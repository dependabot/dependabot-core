# frozen_string_literal: true

require "toml-rb"

require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/source"

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/dep/requirement"
require "dependabot/dep/path_converter"

# Relevant dep docs can be found at:
# - https://github.com/golang/dep/blob/master/docs/Gopkg.toml.md
# - https://github.com/golang/dep/blob/master/docs/Gopkg.lock.md
module Dependabot
  module Dep
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      REQUIREMENT_TYPES = %w(constraint override).freeze

      def parse
        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies
        dependency_set.dependencies
      end

      private

      def manifest_dependencies
        dependency_set = DependencySet.new

        REQUIREMENT_TYPES.each do |type|
          parsed_file(manifest).fetch(type, []).each do |details|
            next if lockfile && !appears_in_lockfile?(details.fetch("name"))
            next if missing_version_in_manifest_and_lockfile(details)

            dependency_set << Dependency.new(
              name: details.fetch("name"),
              version: version_from_declaration(details),
              package_manager: "dep",
              requirements: [{
                requirement: requirement_from_declaration(details),
                file: manifest.name,
                groups: [],
                source: source_from_declaration(details)
              }]
            )
          end
        end

        dependency_set
      end

      def lockfile_dependencies
        dependency_set = DependencySet.new

        parsed_file(lockfile).fetch("projects", []).each do |details|
          dependency_set << Dependency.new(
            name: details.fetch("name"),
            version: version_from_lockfile(details),
            package_manager: "dep",
            requirements: []
          )
        end

        dependency_set
      end

      def version_from_lockfile(details)
        details["version"]&.sub(/^v?/, "") || details.fetch("revision")
      end

      def requirement_from_declaration(declaration)
        unless declaration.is_a?(Hash)
          raise "Unexpected dependency declaration: #{declaration}"
        end

        return if git_declaration?(declaration)

        declaration["version"]
      end

      def source_from_declaration(declaration)
        source = declaration["source"] || declaration["name"]

        git_source_url = git_source(source)

        if git_source_url && git_declaration?(declaration)
          {
            type: "git",
            url: git_source_url,
            branch: declaration["branch"],
            ref: declaration["revision"] || declaration["version"]
          }
        elsif git_declaration?(declaration)
          raise "No git source for a git declaration!"
        else
          {
            type: "default",
            source: source
          }
        end
      end

      def version_from_declaration(declaration)
        lockfile_details =
          parsed_file(lockfile).fetch("projects", []).
          find { |details| details["name"] == declaration.fetch("name") }

        if source_from_declaration(declaration).fetch(:type) == "git"
          lockfile_details["revision"] ||
            version_from_lockfile(lockfile_details)
        else
          version_from_lockfile(lockfile_details)
        end
      end

      def appears_in_lockfile?(dependency_name)
        parsed_file(lockfile).fetch("projects", []).
          any? { |details| details["name"] == dependency_name }
      end

      def git_declaration?(declaration)
        return true if declaration["branch"] || declaration["revision"]
        return false unless declaration["version"]
        return false unless declaration["version"].match?(/^[A-Za-z0-9]/)

        Dep::Requirement.new(declaration["version"])
        false
      rescue Gem::Requirement::BadRequirementError
        true
      end

      def git_source(path)
        Dependabot::Dep::PathConverter.git_url_for_path(path)
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        if e.message == "Cannot detect VCS"
          msg = e.message + " for #{path}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        if e.message.end_with?("Not Found")
          msg = "#{path} returned a 404"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        raise
      end

      def parsed_file(file)
        @parsed_file ||= {}
        @parsed_file[file.name] ||= TomlRB.parse(file.content)
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def manifest
        @manifest ||= get_original_file("Gopkg.toml")
      end

      def lockfile
        @lockfile ||= get_original_file("Gopkg.lock")
      end

      def check_required_files
        %w(Gopkg.toml Gopkg.lock).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      def missing_version_in_manifest_and_lockfile(declaration)
        return false if git_declaration?(declaration)

        lockfile_decl =
          parsed_file(lockfile).
          fetch("projects", []).
          find { |details| details["name"] == declaration["name"] }
        lockfile_decl&.fetch("version", nil).nil?
      end
    end
  end
end

Dependabot::FileParsers.register("dep", Dependabot::Dep::FileParser)
