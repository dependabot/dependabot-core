# frozen_string_literal: true

require "toml-rb"

require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/file_parsers/base"

# Relevant dep docs can be found at:
# - https://github.com/golang/dep/blob/master/docs/Gopkg.toml.md
# - https://github.com/golang/dep/blob/master/docs/Gopkg.lock.md
module Dependabot
  module FileParsers
    module Go
      class Dep < Dependabot::FileParsers::Base
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
            parsed_file(manifest).fetch(type, {}).each do |details|
              dependency_set << Dependency.new(
                name: details.fetch("name"),
                version: nil,
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

          parsed_file(lockfile).fetch("projects", {}).each do |details|
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

          declaration["version"]
        end

        def source_from_declaration(declaration)
          unless declaration.is_a?(Hash)
            raise "Unexpected dependency declaration: #{declaration}"
          end

          source = declaration["source"] || declaration["name"]

          git_source = git_source(source)

          if git_source && (declaration["branch"] || declaration["revision"])
            {
              type: "git",
              url: git_source.url,
              branch: declaration["branch"],
              ref: declaration["revision"]
            }
          else
            {
              type: "default",
              source: source,
              branch: declaration["branch"],
              ref: declaration["revision"]
            }
          end
        end

        def git_source(path)
          updated_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

          # Currently, Dependabot::Source.new will return `nil` if it can't find
          # a git SCH associated with a path. If it is ever extended to handle
          # non-git sources we'll need to add an additional check here.
          Source.from_url(updated_path)
        end

        def parsed_file(file)
          @parsed_file ||= {}
          @parsed_file[file.name] ||= TomlRB.parse(file.content)
        rescue TomlRB::ParseError
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
      end
    end
  end
end
