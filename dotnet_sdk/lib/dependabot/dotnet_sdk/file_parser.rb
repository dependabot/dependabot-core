# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "sorbet-runtime"

module Dependabot
  module DotnetSdk
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        config_dependency_files.each do |config_dependency_file|
          dependency = parse_dependency_file(config_dependency_file)
          dependency_set << dependency if dependency
        end

        dependency_set.dependencies
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

        return unless contents["sdk"]

        Dependabot::Dependency.new(
          name: "dotnet-sdk",
          version: contents["sdk"]["version"],
          package_manager: "dotnet_sdk",
          requirements: [{
            file: dependency_file.name,
            requirement: contents["sdk"]["version"],
            groups: [],
            source: nil
          }],
          metadata: {
            allow_prerelease: contents["sdk"]["allowPrerelease"] || false,
            roll_forward: contents["sdk"]["rollForward"] || "latestPatch"
          }
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def config_dependency_files
        @config_dependency_files ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("global.json")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end
    end
  end
end

Dependabot::FileParsers.register("dotnet_sdk", Dependabot::DotnetSdk::FileParser)
