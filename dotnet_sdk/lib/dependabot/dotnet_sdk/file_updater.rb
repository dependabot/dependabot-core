# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "sorbet-runtime"

module Dependabot
  module DotnetSdk
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/^global\.json$/]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        contents = update

        updated_files << updated_file(file: global_json, content: contents) if file_changed?(global_json)

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        # Dockerfiles will only ever be updating a single dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No global.json configuration!"
      end

      sig { returns(Dependabot::DependencyFile) }
      def global_json
        T.must(dependency_files.find { |f| f.name == "global.json" })
      end

      sig { returns(String) }
      def update
        T.must(global_json.content).gsub(T.must(dependency.previous_version), T.must(dependency.version))
      end
    end
  end
end

Dependabot::FileUpdaters.register("dotnet_sdk", Dependabot::DotnetSdk::FileUpdater)
