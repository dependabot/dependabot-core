# frozen_string_literal: true
require "gemnasium/parser"
require "bump/dependency"
require "bump/dependency_file_parsers/base"
require "bump/dependency_file_fetchers/ruby"

module Bump
  module DependencyFileParsers
    class Ruby < Base
      def parse
        gemfile_parser.dependencies.map do |dependency|
          # Ignore dependencies with multiple requirements, since they would
          # cause trouble at the gem update step. TODO: fix!
          next if dependency.requirement.requirements.count > 1

          # Ignore gems which appear in the Gemfile but not the Gemfile.lock.
          # For instance, if a gem specifies `platform: [:windows]`, and the
          # Gemfile.lock is generated on a Linux machine.
          next if dependency_version(dependency.name).nil?

          Dependency.new(
            name: dependency.name,
            version: dependency_version(dependency.name).to_s,
            language: "ruby"
          )
        end.reject(&:nil?)
      end

      private

      attr_reader :gemfile, :lockfile

      def required_files
        Bump::DependencyFileFetchers::Ruby.required_files
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile")
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock")
      end

      def gemfile_parser
        Gemnasium::Parser.gemfile(gemfile.content)
      end

      # Parse the Gemfile.lock to get the gem version. Better than just relying
      # on the dependency's specified version, which may have had a ~> matcher.
      def dependency_version(dependency_name)
        @parsed_lockfile ||= Bundler::LockfileParser.new(lockfile.content)

        if dependency_name == "bundler"
          return Gem::Version.new(Bundler::VERSION)
        end

        # The safe navigation operator is necessary because not all files in
        # the Gemfile will appear in the Gemfile.lock. For instance, if a gem
        # specifies `platform: [:windows]`, and the Gemfile.lock is generated
        # on a Linux machine, the gem will be not appear in the lockfile.
        @parsed_lockfile.specs.
          find { |spec| spec.name == dependency_name }&.
          version
      end
    end
  end
end
