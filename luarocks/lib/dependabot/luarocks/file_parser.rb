# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/luarocks/requirement"
require "dependabot/luarocks/version"

module Dependabot
  module Luarocks
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      DEPENDENCY_KEYS = T.let(%w(dependencies build_dependencies).freeze, T::Array[String])

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_map = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

        rockspec_files.each do |file|
          parse_dependencies(file).each do |entry|
            name = entry.fetch(:name)
            dependency_map[name] ||= { requirements: [] }

            T.must(dependency_map[name])[:requirements] << {
              requirement: entry[:requirement],
              file: file.name,
              groups: entry[:groups],
              source: nil
            }
          end
        end

        dependency_map.map do |name, details|
          Dependency.new(
            name: name,
            requirements: details.fetch(:requirements),
            package_manager: "luarocks",
            version: nil
          )
        end
      end

      private

      sig { override.void }
      def check_required_files
        return if rockspec_files.any?

        raise Dependabot::DependencyFileNotFound, "No .rockspec files found."
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def rockspec_files
        dependency_files.select { |f| f.name.end_with?(".rockspec") }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def parse_dependencies(file)
        content = T.must(file.content)
        DEPENDENCY_KEYS.flat_map do |key|
          block = extract_table(content, key)
          next [] unless block

          parse_dependency_block(block, key)
        end
      end

      sig { params(content: String, key: String).returns(T.nilable(String)) }
      def extract_table(content, key)
        regex = /#{Regexp.escape(key)}\s*=\s*\{(?<body>.*?)\}/m
        match = regex.match(content)
        match[:body] if match
      end

      sig { params(block: String, group: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def parse_dependency_block(block, group)
        captures_array = block.scan(/["']([^"']+)["']/).map { |capture| Array(capture) }
        captures = T.let(captures_array, T::Array[T::Array[String]])

        captures.filter_map do |capture|
          dependency_string = capture.first&.strip
          next if dependency_string.nil? || dependency_string.empty?

          name, requirement = parse_dependency_string(dependency_string)
          next unless name

          {
            name: name,
            requirement: requirement,
            groups: [group]
          }
        end
      end

      sig { params(dependency_string: String).returns([T.nilable(String), T.nilable(String)]) }
      def parse_dependency_string(dependency_string)
        if dependency_string =~ %r{\A([A-Za-z0-9_.\-\/]+)\s+(.*)\z}
          name = T.must(Regexp.last_match(1))
          requirement = T.must(Regexp.last_match(2)).strip
          requirement = "= #{requirement}" unless requirement.match?(/\A[<>~=]/)
          [name, requirement]
        else
          [dependency_string, nil]
        end
      end
    end
  end
end

Dependabot::FileParsers.register("luarocks", Dependabot::Luarocks::FileParser)
