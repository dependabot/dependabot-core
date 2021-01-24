# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Helm
    class FileParser < Dependabot::FileParsers::Base
      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        dependencies.each do |d|
          reqs = [{
            file: chart_yaml.name,
            groups: [],
            requirement: d["version"],
            source: d["repository"]
          }]

          dependency = Dependency.new(
            name: d["name"],
            package_manager: "helm",
            requirements: reqs,
            version: d["version"]
          )
          dependency_set << dependency if dependency
        end

        dependency_set.dependencies
      end

      private

      def chart_yaml
        @chart_yaml ||= get_original_file("Chart.yaml")
      end

      def check_required_files
        raise "No Chart.yaml!" unless chart_yaml
      end

      def dependencies
        @dependencies ||= Array(Psych.load(chart_yaml.content)["dependencies"])
      end
    end
  end
end

Dependabot::FileParsers.register("helm", Dependabot::Helm::FileParser)
