# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "sorbet-runtime"
require "dependabot/dotnet_sdk/package_manager"
require "dependabot/dotnet_sdk/language"

module Dependabot
  module DotnetSdk
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        config_dependency_files.each do |dependency_file|
          dependency = parse_dependency_file(dependency_file)
          dependency_set << dependency if dependency
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: dotnetsdk
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_dependency_file(dependency_file)
        return unless dependency_file.content

        begin
          contents = JSON.parse(T.must(dependency_file.content))
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
        end

        sdk_info = contents["sdk"]
        return unless sdk_info

        version = sdk_info["version"]
        return unless version

        Dependabot::Dependency.new(
          name: "dotnet-sdk",
          version: version,
          package_manager: "dotnet_sdk",
          requirements: [{
            file: dependency_file.name,
            requirement: version,
            groups: [],
            source: nil
          }],
          metadata: {
            allow_prerelease: sdk_info["allowPrerelease"] || false,
            roll_forward: sdk_info["rollForward"] || "latestPatch"
          }
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def dotnetsdk
        DotnetSDK.new(T.must(sdk_version))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def config_dependency_files
        @config_dependency_files ||= T.let(
          dependency_files.filter { |f| f.name.end_with?("global.json") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        raise "No dependency files!" if dependency_files.empty?
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        DotNetSdkPackageManager.new
      end

      sig { returns(T.nilable(String)) }
      def sdk_version
        @sdk_version ||= T.let(
          config_dependency_files.filter_map do |dependency_file|
            contents = JSON.parse(T.must(dependency_file.content))
            contents.dig("sdk", "version")
          rescue JSON::ParserError
            raise Dependabot::DependencyFileNotParseable, dependency_file.path
          end.first,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("dotnet_sdk", Dependabot::DotnetSdk::FileParser)
