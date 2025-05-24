require "toml-rb"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Julia
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [
          /Project\.toml$/i,
          /JuliaProject\.toml$/i,
          /Manifest(?:-v[\d.]+)?\.toml$/i
        ]
      end

      def updated_dependency_files
        updated_files = []

        manifest_files.each do |file|
          next unless file_changed?(file)

          updated_files << updated_file(
            file: file,
            content: updated_manifest_content(file)
          )
        end

        raise "No files changed!" if updated_files.none?
        updated_files
      end

      private

      def check_required_files
        raise "No Project.toml!" unless get_original_file("Project.toml")
      end

      def manifest_files
        dependency_files.select { |f| f.name.match?(FileFetcher::MANIFEST_REGEX) }
      end

      def updated_manifest_content(file)
        content = file.content
        dependencies.each do |dependency|
          requirements = dependency.requirements.find { |r| r[:file] == file.name }
          next unless requirements

          toml = TomlRB.parse(content)
          TYPES.each do |type|
            next unless (deps = toml.dig("deps", type))
            next unless (dep_details = deps[dependency.name])
            next unless dep_details.is_a?(Hash)

            dep_details["version"] = dependency.version
          end
          content = TomlRB.dump(toml)
        end
        content
      end
    end
  end
end

Dependabot::FileUpdaters.register("julia", Dependabot::Julia::FileUpdater)
