# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/ecosystem"
require "dependabot/silent/package_manager"
require "sorbet-runtime"

module SilentPackageManager
  class FileParser < Dependabot::FileParsers::Base
    extend T::Sig

    require "dependabot/file_parsers/base/dependency_set"

    sig { override.returns(T::Array[Dependabot::Dependency]) }
    def parse
      dependency_set = DependencySet.new

      JSON.parse(manifest_content).each do |name, info|
        dependency_set << parse_single_dependency(name, info) if info.key?("version")
        dependency_set << parse_multiple_dependency(name, info) if info.key?("versions")
      end

      dependency_set.dependencies
    rescue JSON::ParserError
      raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
    end

    sig { returns(Dependabot::Ecosystem::VersionManager) }
    def package_manager
      meta_data = JSON.parse(manifest_content)["silent"]
      silent_version = if meta_data.nil?
                         "2"
                       else
                         meta_data["version"]
                       end
      Dependabot::Silent::PackageManager.new(silent_version)
    rescue JSON::ParserError
      raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
    end

    private

    sig { params(name: String, info: String).returns(Dependabot::Dependency) }
    def parse_single_dependency(name, info)
      Dependabot::Dependency.new(
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

    # To match the behavior of npm_and_yarn, this returns one Dependency but has
    # a metadata field that includes all the versions of the Dependency.
    sig { params(name: String, info: String).returns(Dependabot::Dependency) }
    def parse_multiple_dependency(name, info)
      dependencies = Array(info["versions"]).map do |version|
        info["version"] = version
        parse_single_dependency(name, info)
      end
      T.must(dependencies.last).metadata[:all_versions] = dependencies
      T.must(dependencies.last)
    end

    sig { returns(String) }
    def manifest_content
      T.must(T.must(dependency_files.first).content)
    end

    sig { override.void }
    def check_required_files
      # Just check if there are any files at all.
      return if dependency_files.any?

      raise "No dependency files!"
    end
  end
end

Dependabot::FileParsers.register("silent", SilentPackageManager::FileParser)
