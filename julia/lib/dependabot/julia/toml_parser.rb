# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "toml-rb"

module Dependabot
  module Julia
    class TomlParser < Dependabot::FileParsers::Base
      SIMPLE_VER = /\A(\d+)(?:\.(\d+))?(?:\.(\d+))?\z/

      def parse
        direct + indirect
      end

      private

      def direct
        deps = project["deps"] || {}
        compat = project["compat"] || {}
        deps.map do |name, uuid|
          Dependency.new(
            name: name,
            package_manager: "julia",
            version_string: manifest_version(name, uuid),
            requirements: [{
              file: project_file.name,
              requirement: normalise_req(compat[name] || "0"),
              groups: ["dependencies"]
            }]
          )
        end
      end

      def indirect
        return [] unless manifest_file
        manifest.keys.filter { |k| k =~ /^[A-Z]/ && !direct_names.include?(k) }.map do |name|
          stanza = manifest[name].find { |s| s["version"] }
          Dependency.new(
            name: name,
            package_manager: "julia",
            version_string: stanza["version"],
            requirements: []
          )
        end
      end

      def project_file
        get_original_file("Project.toml") || get_original_file("JuliaProject.toml")
      end

      def manifest_file
        @manifest_file ||= dependency_files.find { |f| f.name.match?(ProjectFileFetcher::MF_RE) }
      end

      def project
        @project ||= TomlRB.parse(project_file.content)
      end

      def manifest
        @manifest ||= manifest_file ? TomlRB.parse(manifest_file.content) : {}
      end

      def direct_names
        @direct_names ||= project.fetch("deps", {}).keys
      end

      def manifest_version(name, uuid)
        return nil unless manifest_file
        stanza = manifest[name]&.find { |s| s["uuid"] == uuid && s["version"] } ||
                manifest[name]&.find { |s| s["version"] }
        stanza&.fetch("version", nil)
      end

      def normalise_req(spec)
        return spec if spec.match?(/[<>=~^,]/)
        m = SIMPLE_VER.match(spec) or return spec
        major, minor, patch = m.captures.map { |v| v || "0" }
        upper = (major == "0") ?
                "0.#{minor.to_i + 1}.0-0" :
                "#{major.to_i + 1}.0.0-0"
        ">= #{major}.#{minor}.#{patch}, < #{upper}"
      end

      def check_required_files
        project_file || raise("No Project.toml")
      end
    end
  end
end

Dependabot::FileParsers.register("julia", Dependabot::Julia::TomlParser)
