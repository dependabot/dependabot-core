# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/uv/file_updater"

module Dependabot
  module Uv
    class FileUpdater < Dependabot::FileUpdaters::Base
      class UvVersionFileUpdater
        extend T::Sig

        REQUIRED_VERSION_REGEX = T.let(
          /(?<prefix>required-version\s*=\s*["'])(?<constraint>[^"']+)(?<suffix>["'])/,
          Regexp
        )

        sig { returns(T::Array[Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig do
          params(
            dependencies: T::Array[Dependency],
            dependency_files: T::Array[DependencyFile]
          ).void
        end
        def initialize(dependencies:, dependency_files:)
          @dependencies = dependencies
          @dependency_files = dependency_files
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          updated_files = []

          uv_tool_dependencies.each do |dep|
            dep.requirements.each do |new_req|
              old_req = find_previous_requirement(dep, new_req[:file])
              next unless old_req
              next if new_req[:requirement] == old_req[:requirement]

              file = dependency_files.find { |f| f.name == new_req[:file] }
              next unless file

              updated_content = update_required_version(
                T.must(file.content),
                old_req[:requirement],
                new_req[:requirement],
                new_req[:file]
              )

              next if updated_content == file.content

              updated_files << updated_file(file: file, content: updated_content)
            end
          end

          updated_files
        end

        private

        sig { returns(T::Array[Dependency]) }
        def uv_tool_dependencies
          dependencies.select { |dep| dep.name == "uv" }
        end

        sig do
          params(
            dep: Dependency,
            filename: String
          ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def find_previous_requirement(dep, filename)
          return nil unless dep.previous_requirements

          T.must(dep.previous_requirements).find { |r| r[:file] == filename }
        end

        sig do
          params(
            content: String,
            old_requirement: String,
            new_requirement: String,
            filename: String
          ).returns(String)
        end
        def update_required_version(content, old_requirement, new_requirement, filename)
          if filename == "pyproject.toml"
            update_in_tool_uv_section(content, old_requirement, new_requirement)
          else
            replace_required_version(content, old_requirement, new_requirement)
          end
        end

        sig { params(content: String, old_requirement: String, new_requirement: String).returns(String) }
        def update_in_tool_uv_section(content, old_requirement, new_requirement)
          lines = content.lines
          section_start = lines.index { |l| l.strip.match?(/^\[tool\.uv\]\s*(#.*)?$/) }
          return content unless section_start

          section_end = T.must(lines[(section_start + 1)..]).index { |l| l.strip.match?(/^\[/) }
          section_end = section_end ? section_start + 1 + section_end : lines.length

          before = T.must(lines[0...section_start]).join
          section = T.must(lines[section_start...section_end]).join
          after = T.must(lines[section_end..]).join

          before + replace_required_version(section, old_requirement, new_requirement) + after
        end

        sig { params(content: String, old_requirement: String, new_requirement: String).returns(String) }
        def replace_required_version(content, old_requirement, new_requirement)
          content.gsub(REQUIRED_VERSION_REGEX) do
            match = T.must(Regexp.last_match)
            if match[:constraint] == old_requirement
              "#{match[:prefix]}#{new_requirement}#{match[:suffix]}"
            else
              match[0].to_s
            end
          end
        end

        sig { params(file: DependencyFile, content: String).returns(DependencyFile) }
        def updated_file(file:, content:)
          updated = file.dup
          updated.content = content
          updated
        end
      end
    end
  end
end
