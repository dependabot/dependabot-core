# frozen_string_literal: true
require "gemnasium/parser"
require "bump/dependency"

module Bump
  module DependencyFileParsers
    class Ruby
      def initialize(dependency_files:)
        @gemfile = dependency_files.find { |f| f.name == "Gemfile" }
        raise "No Gemfile!" unless @gemfile
      end

      def parse
        parser.dependencies.map do |dependency|
          # Ignore dependencies with multiple requirements, since they would
          # cause trouble at the gem update step
          next if dependency.requirement.requirements.count > 1

          version = dependency.requirement.to_s.match(/[\d\.]+/)[0]
          Dependency.new(
            name: dependency.name,
            version: version,
            language: "ruby"
          )
        end.reject(&:nil?)
      end

      private

      def parser
        Gemnasium::Parser.gemfile(@gemfile.content)
      end
    end
  end
end
