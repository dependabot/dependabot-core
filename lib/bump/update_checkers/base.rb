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
        return false if dependency_version.nil?
        Gem::Version.new(latest_version) > dependency_version
      end

      def updated_dependency
        Dependency.new(
          name: dependency.name,
          version: latest_version,
          previous_version: dependency_version.to_s,
          language: dependency.language
        )
      end

      def latest_version
        raise NotImplementedError
      end

      def dependency_version
        raise NotImplementedError
      end
    end
  end
end
