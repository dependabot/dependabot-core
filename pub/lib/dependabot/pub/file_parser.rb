# typed: strict
# frozen_string_literal: true

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/dependency"
require "dependabot/pub/version"
require "dependabot/pub/helpers"
require "sorbet-runtime"

module Dependabot
  module Pub
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      include Dependabot::Pub::Helpers

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        list.map do |d|
          dependency_set << parse_listed_dependency(d)
        end
        dependency_set.dependencies.sort_by(&:name)
      end

      private

      sig { override.void }
      def check_required_files
        raise "No pubspec.yaml!" unless get_original_file("pubspec.yaml")
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def list
        @list ||= T.let(dependency_services_list, T.nilable(T::Array[Dependabot::Dependency]))
      end
    end
  end
end

Dependabot::FileParsers.register("pub", Dependabot::Pub::FileParser)
