# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/sbt/file_parser"

module Dependabot
  module Sbt
    class FileParser < Dependabot::FileParsers::Base
      class PropertyValueFinder
        extend T::Sig

        # Matches: val someVersion = "1.2.3"
        # Also:   val someVersion: String = "1.2.3"
        # Also:   lazy val someVersion = "1.2.3"
        VAL_DECLARATION_REGEX = T.let(
          /(?:^|\s)(?:lazy\s+)?val\s+(?<name>\w+)(?:\s*:\s*String)?\s*=\s*"(?<value>[^"]+)"/,
          Regexp
        )

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @properties = T.let({}, T::Hash[String, T::Hash[String, T::Hash[Symbol, String]]])
        end

        sig do
          params(property_name: String, callsite_buildfile: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, String]))
        end
        def property_details(property_name:, callsite_buildfile:)
          # Look in the callsite file first, then fall back to the root build.sbt,
          # then check project/*.scala build definition files
          all_files = [callsite_buildfile, top_level_buildfile].compact
          all_files += project_scala_files
          all_files.uniq!
          all_files.each do |file|
            details = properties(file).fetch(property_name, nil)
            return details if details
          end
          nil
        end

        sig { params(property_name: String, callsite_buildfile: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def property_value(property_name:, callsite_buildfile:)
          property_details(
            property_name: property_name,
            callsite_buildfile: callsite_buildfile
          )&.fetch(:value)
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { params(buildfile: Dependabot::DependencyFile).returns(T::Hash[String, T::Hash[Symbol, String]]) }
        def properties(buildfile)
          @properties[buildfile.name] ||= fetch_val_declarations(buildfile)
        end

        sig { params(buildfile: Dependabot::DependencyFile).returns(T::Hash[String, T::Hash[Symbol, String]]) }
        def fetch_val_declarations(buildfile)
          props = T.let({}, T::Hash[String, T::Hash[Symbol, String]])

          prepared_content(buildfile).scan(VAL_DECLARATION_REGEX) do
            captures = T.must(Regexp.last_match).named_captures
            name = T.must(captures.fetch("name"))
            value = T.must(captures.fetch("value"))

            unless props.key?(name)
              props[name] = {
                value: value,
                declaration_string: Regexp.last_match.to_s.strip,
                file: buildfile.name
              }
            end
          end

          props
        end

        sig { params(buildfile: Dependabot::DependencyFile).returns(String) }
        def prepared_content(buildfile)
          T.must(buildfile.content)
           .gsub(%r{(?<=^|\s)//.*$}, "\n")
           .gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def top_level_buildfile
          @top_level_buildfile ||= T.let(
            dependency_files.find { |f| f.name == "build.sbt" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def project_scala_files
          @project_scala_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?(".scala") && f.name.start_with?("project/") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end
      end
    end
  end
end
