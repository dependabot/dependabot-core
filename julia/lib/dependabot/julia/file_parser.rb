# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "toml-rb"

module Dependabot
  module Julia
    class FileParser < Dependabot::FileParsers::Base
      SIMPLE_VER = /\A(\d+)(?:\.(\d+))?(?:\.(\d+))?\z/

      sig { override.returns(T::Array[Dependency]) }
      def parse
        direct + indirect
      end

      private

      sig { returns(T::Array[Dependency]) }
      def direct
        deps = project["deps"] || {}
        compat = project["compat"] || {}
        deps.map do |name, uuid|
          Dependency.new(
            name: name,
            package_manager: "julia",
            version: manifest_version(name, uuid),
            requirements: [{
              file: T.must(project_file).name,
              requirement: normalise_req(compat[name] || "0"),
              groups: ["dependencies"]
            }]
          )
        end
      end

      sig { returns(T::Array[Dependency]) }
      def indirect
        return [] unless manifest_file

        manifest.keys.filter { |k| k =~ /^[A-Z]/ && !direct_names.include?(k) }.map do |name|
          stanza = manifest[name].find { |s| s["version"] }
          Dependency.new(
            name: name,
            package_manager: "julia",
            version: stanza["version"],
            requirements: []
          )
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        @project_file ||= T.let(
          get_original_file("Project.toml") || get_original_file("JuliaProject.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_file
        @manifest_file ||= T.let(
          dependency_files.find { |f| f.name.match?(Shared::MANIFEST_REGEX) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def project
        @project ||= T.let(TomlRB.parse(T.must(project_file).content), T.nilable(T::Hash[String, T.untyped]))
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def manifest
        @manifest ||= T.let(
          manifest_file ? TomlRB.parse(T.must(manifest_file).content) : {},
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T::Array[String]) }
      def direct_names
        @direct_names ||= T.let(project.fetch("deps", {}).keys, T.nilable(T::Array[String]))
      end

      sig { params(name: String, uuid: String).returns(T.nilable(String)) }
      def manifest_version(name, uuid)
        return nil unless manifest_file

        stanza = manifest[name]&.find { |s| s["uuid"] == uuid && s["version"] } ||
                 manifest[name]&.find { |s| s["version"] }
        stanza&.fetch("version", nil)
      end

      sig { params(spec: T.nilable(String)).returns(T.untyped) }
      def normalise_req(spec)
        return spec if T.must(spec).match?(/[<>=~^,]/)

        # Handle simple version number format (e.g. "1.2.3")
        m = T.must(spec).match(/^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?$/)
        return spec unless m

        # Convert captures that might be nil to string values
        captures = m.captures
        major = captures[0] || "0"
        minor = captures[1] || "0"
        patch = captures[2] || "0"
        "^#{major}.#{minor}.#{patch}"
      end

      sig { override.void }
      def check_required_files
        project_file || raise("No Project.toml")
      end
    end
  end
end
