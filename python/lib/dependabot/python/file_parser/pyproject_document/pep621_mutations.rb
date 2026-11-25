# typed: strong
# frozen_string_literal: true

require "dependabot/python/file_parser/pyproject_document"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class PyprojectDocument
        PEP508_PREFIX = /\A(?<prefix>(?<name>[a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?)(?:\[[^\]]*\])?)/i

        sig { params(versions: T::Hash[String, String]).void }
        def freeze_pep621_versions(versions)
          dependency_arrays(include_groups: false, strict: false).each do |entries|
            next unless entries.all?(String)

            entries.map! do |entry|
              declaration = PyprojectValueParser.string(entry, "PEP 621 dependency")
              match = declaration.match(PEP508_PREFIX)
              version = match && versions[NameNormaliser.normalise(T.must(match[:name]))]
              version ? pin_pep508_entry(declaration, version) : declaration
            end
          end
        end

        sig { params(lock: PoetryLock, excluding: T::Array[String]).void }
        def freeze_locked_pep621_dependencies(lock:, excluding:)
          dependency_arrays(include_groups: false, strict: true).each do |entries|
            entries.map! do |entry|
              declaration = PyprojectValueParser.string(entry, "PEP 621 dependency")
              match = declaration.match(PEP508_PREFIX)
              next declaration unless match

              name = NameNormaliser.normalise(T.must(match[:name]))
              next declaration if excluding.include?(name)
              next declaration if lock.records_for(name, &:itself).size > 1

              record = lock.record_for(name, &:itself)
              record ? pin_pep508_entry(declaration, record.version) : declaration
            end
          end
        end

        sig { params(name: String, requirement: String).returns(Integer) }
        def replace_pep621_requirement(name:, requirement:)
          changed = 0
          dependency_arrays(include_groups: true, strict: false).each do |entries|
            entries.map! do |entry|
              next entry unless entry.is_a?(String)

              match = entry.match(PEP508_PREFIX)
              next entry unless match && NameNormaliser.normalise(T.must(match[:name])) == name

              changed += 1
              prefix = T.must(match[:prefix])
              head, separator, tail = entry[prefix.length..].to_s.partition(";")
              marker = separator.empty? ? "" : "#{head[head.rstrip.length..]};#{tail}"
              "#{prefix}#{requirement}#{marker}"
            end
          end
          changed
        end

        sig { params(main: T.nilable(String), extras: T::Hash[String, String], groups: T::Hash[String, String]).void }
        def append_pep621_pins(main:, extras:, groups:)
          project = mutable_section(@data, "project", "project")
          return unless project

          if main
            entries = project["dependencies"]
            dependencies = entries.nil? ? [] : PyprojectValueParser.array(entries, "project.dependencies")
            project["dependencies"] = dependencies << main
          end
          optional = T.must(
            mutable_section(project, "optional-dependencies", "project.optional-dependencies", create: true)
          )
          append_group_pins(optional, extras)
          return if groups.empty?

          table = T.must(mutable_section(@data, "dependency-groups", "dependency-groups", create: true))
          append_group_pins(table, groups)
        end

        private

        sig { params(include_groups: T::Boolean, strict: T::Boolean).returns(T::Array[T::Array[Object]]) }
        def dependency_arrays(include_groups:, strict:)
          project = mutable_section(@data, "project", "project")
          return [] unless project

          arrays = T.let([], T::Array[T::Array[Object]])
          main = attached_array(project, "dependencies", "project.dependencies", strict: strict)
          arrays << main if main
          optional = mutable_section(project, "optional-dependencies", "project.optional-dependencies")
          optional&.each_key do |name|
            entries = attached_array(optional, name, "project.optional-dependencies.#{name}", strict: strict)
            arrays << entries if entries
          end
          if include_groups
            groups = mutable_section(@data, "dependency-groups", "dependency-groups")
            groups&.each_key do |name|
              entries = attached_array(groups, name, "dependency-groups.#{name}", strict: strict)
              arrays << entries if entries
            end
          end
          arrays
        end

        sig do
          params(
            parent: PyprojectValueParser::ObjectHash, key: String, context: String, strict: T::Boolean
          ).returns(T.nilable(T::Array[Object]))
        end
        def attached_array(parent, key, context, strict:)
          value = parent[key]
          return if value.nil? || (!strict && !value.is_a?(Array))

          entries = PyprojectValueParser.array(value, context)
          parent[key] = entries
          entries
        end

        sig { params(table: PyprojectValueParser::ObjectHash, pins: T::Hash[String, String]).void }
        def append_group_pins(table, pins)
          pins.each do |name, pin|
            key = table.keys.find { |entry| normalized_group(entry) == normalized_group(name) } || name
            value = table[key]
            entries = value.nil? ? [] : PyprojectValueParser.array(value, "dependency group #{key}")
            table[key] = entries << pin
          end
        end

        sig { params(name: String).returns(String) }
        def normalized_group(name)
          name.downcase.gsub(/[-_.]+/, "-")
        end

        sig { params(entry: String, version: String).returns(String) }
        def pin_pep508_entry(entry, version)
          match = entry.match(PEP508_PREFIX)
          return entry unless match

          prefix = T.must(match[:prefix])
          rest = T.must(entry[prefix.length..])
          return entry if rest.match?(/\A\s*@\s/)

          marker_match = rest.match(/(\s*;.*)/)
          marker = marker_match ? marker_match[1] : ""
          "#{prefix}==#{version}#{marker}"
        end
      end
    end
  end
end
