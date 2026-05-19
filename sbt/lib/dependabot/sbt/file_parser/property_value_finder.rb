# typed: strong
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
          # Handle dotted references like "V.scalafixVersion" by looking up the member name
          if property_name.include?(".")
            return dotted_property_details(property_name: property_name, callsite_buildfile: callsite_buildfile)
          end

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

        # Resolves dotted property references like "Versions.catsVersion" or "V.scala212".
        # Searches for `val <member> = "..."` inside `object <ObjectName> { ... }` blocks
        # across all dependency files.
        sig do
          params(property_name: String, callsite_buildfile: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, String]))
        end
        def dotted_property_details(property_name:, callsite_buildfile:)
          parts = property_name.split(".")
          return nil unless parts.length == 2

          object_name = T.must(parts.first)
          member_name = T.must(parts.last)

          # Resolve val aliases (e.g. "val V = BuildInfo" means V.x should look in object BuildInfo)
          resolved_names = resolve_object_aliases(object_name, callsite_buildfile)

          all_files = [callsite_buildfile, top_level_buildfile].compact
          all_files += project_scala_files
          all_files.uniq!

          resolved_names.each do |resolved_name|
            all_files.each do |file|
              content = prepared_content(file)
              object_regex = /object\s+#{Regexp.quote(resolved_name)}\b[^{]*\{(?<body>[^}]*)\}/m
              content.scan(object_regex) do
                body = T.must(Regexp.last_match).named_captures.fetch("body")
                member_regex = /(?:^|\s)(?:lazy\s+)?val\s+#{Regexp.quote(member_name)}/
                member_value_regex = /#{member_regex}(?:\s*:\s*String)?\s*=\s*"(?<value>[^"]+)"/
                member_match = body&.match(member_value_regex)
                next unless member_match

                declaration_string = member_match.to_s.strip
                return {
                  value: T.must(member_match[:value]),
                  declaration_string: declaration_string,
                  file: file.name
                }
              end
            end
          end

          nil
        end

        # Resolves val aliases like "val V = BuildInfo" → returns ["V", "BuildInfo"]
        # so that dotted references like V.member can look in object BuildInfo.
        sig { params(name: String, callsite_buildfile: Dependabot::DependencyFile).returns(T::Array[String]) }
        def resolve_object_aliases(name, callsite_buildfile)
          names = [name]

          all_files = [callsite_buildfile, top_level_buildfile].compact
          all_files += project_scala_files
          all_files.uniq!

          all_files.each do |file|
            prepared_content(file).scan(/(?:^|\s)(?:lazy\s+)?val\s+#{Regexp.quote(name)}\s*=\s*(?<target>[A-Z]\w*)/) do
              target = T.must(Regexp.last_match).named_captures.fetch("target")
              names << T.must(target) unless names.include?(target)
            end
          end

          names
        end

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
