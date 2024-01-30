# typed: true
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module SilentPackageManager
  class FileParser < Dependabot::FileParsers::Base
    require "dependabot/file_parsers/base/dependency_set"

    def parse
      dependency_set = DependencySet.new

      JSON.parse(manifest_content).each do |name, info|
        dependency_set << Dependabot::Dependency.new(
          name: name,
          version: info["version"],
          package_manager: "silent",
          requirements: [{
            requirement: info["version"],
            file: T.must(dependency_files.first).name,
            groups: [info["group"]].compact,
            source: nil
          }]
        )
      end

      dependency_set.dependencies
    rescue JSON::ParserError
      raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
    end

    private

    def manifest_content
      T.must(T.must(dependency_files.first).content)
    end

    def check_required_files
      # Just check if there are any files at all.
      return if dependency_files.any?

      raise "No dependency files!"
    end
  end
end

Dependabot::FileParsers.register("silent", SilentPackageManager::FileParser)
