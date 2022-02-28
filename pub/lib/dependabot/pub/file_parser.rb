# frozen_string_literal: true

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/dependency"
require "dependabot/pub/version"
require "dependabot/pub/helpers"

module Dependabot
  module Pub
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      include Dependabot::Pub::Helpers

      def parse
        dependency_set = DependencySet.new
        list.map do |d|
          dependency_set << to_dependency(d)
        end
        dependency_set.dependencies.sort_by(&:name)
      end

      private

      def check_required_files
        raise "No pubspec.yaml!" unless get_original_file("pubspec.yaml")
      end

      def list
        @list ||= dependency_services_list
      end
    end
  end
end

Dependabot::FileParsers.register("pub", Dependabot::Pub::FileParser)
