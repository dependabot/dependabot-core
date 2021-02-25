# frozen_string_literal: true

require "yaml"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "dependabot/haskell/version"

module Dependabot
  module Haskell
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new

        cabal_files.each do |file|
          dependency_set += file_dependencies(file)
        end

        dependency_set.dependencies
      end

      private

      CABAL_DEP_REGEX = /\s+(?<dep>(?<repo>[\w\d\-]+)\s+(?<reqs>[><=(][><=&|()\d\.\*\s]+))/

      def file_dependencies(file)
        dependency_set = DependencySet.new
        file.content.scan(CABAL_DEP_REGEX).map do |tuple|
          dependency_set << build_dependency(file, tuple)
      end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def build_dependency(file, tuple)
        (dep, name, reqs_str) = tuple
        reqs_str = reqs_str.strip

        Dependency.new(
          name: name,
          version: reqs_str,
          requirements: [{
            requirement: reqs_str,
            groups: [], # we don't have this (its dev vs non-dev)
            source: nil, # cabal doesn't do git sources
            file: file.name,
            metadata: { declaration_string: dep.strip }
          }],
          package_manager: "haskell"
        )
      end

      def cabal_files
        dependency_files.select { |f| f.name.end_with?(".cabal") }
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No cabal files!"
      end
    end
  end
end

Dependabot::FileParsers.
  register("haskell", Dependabot::Haskell::FileParser)
