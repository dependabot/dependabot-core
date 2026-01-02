# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/opam/version"

module Dependabot
  module Opam
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require_relative "file_parser/opam_parser"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        opam_files.each do |file|
          dependencies += parse_opam_file(file)
        end

        dependencies.uniq
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def opam_files
        dependency_files.select { |f| f.name.end_with?(".opam") || f.name == "opam" }
      end

      sig { params(file: DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_opam_file(file)
        content = T.must(file.content)

        # Parse depends field
        depends = OpamParser.extract_depends(content)
        dependencies = depends.map do |dep_name, constraint|
          build_dependency(dep_name, constraint, file.name)
        end

        # Parse depopts field (optional dependencies)
        depopts = OpamParser.extract_depopts(T.must(file.content))
        depopts.each do |dep_name, constraint|
          dependencies << build_dependency(dep_name, constraint, file.name, optional: true)
        end

        dependencies
      end

      sig do
        params(
          name: String,
          constraint: T.nilable(String),
          filename: String,
          optional: T::Boolean
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(name, constraint, filename, optional: false)
        requirements = if constraint
                         [{
                           requirement: constraint,
                           groups: [],
                           source: nil,
                           file: filename
                         }]
                       else
                         []
                       end

        metadata = optional ? { "optional" => "true" } : {}

        Dependabot::Dependency.new(
          name: name,
          version: nil,
          requirements: requirements,
          package_manager: "opam",
          metadata: metadata
        )
      end

      sig { override.returns(T::Boolean) }
      def check_required_files # rubocop:disable Naming/PredicateMethod
        opam_files.any?
      end
    end
  end
end

Dependabot::FileParsers
  .register("opam", Dependabot::Opam::FileParser)
