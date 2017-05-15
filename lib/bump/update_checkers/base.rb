# frozen_string_literal: true
require "json"

module Bump
  module UpdateCheckers
    class Base
      attr_reader :dependency, :dependency_files

      def initialize(dependency:, dependency_files:)
        @dependency = dependency
        @dependency_files = dependency_files
      end

      def needs_update?
        latest_version && latest_version > Gem::Version.new(dependency.version)
      end

      def updated_dependency
        Dependency.new(
          name: dependency.name,
          version: latest_version.to_s,
          previous_version: dependency.version,
          language: dependency.language
        )
      end

      def latest_version
        raise NotImplementedError
      end
    end
  end
end
