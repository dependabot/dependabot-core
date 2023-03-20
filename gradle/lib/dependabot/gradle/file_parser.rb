# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/gradle/version"

# The best Gradle documentation is at:
# - https://docs.gradle.org/current/dsl/org.gradle.api.artifacts.dsl.
#   DependencyHandler.html
#
# In addition, documentation on plugins is at:
# - https://docs.gradle.org/current/userguide/plugins.html
module Dependabot
  module Gradle
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/property_value_finder"

      SUPPORTED_BUILD_FILE_NAMES = %w(build.gradle build.gradle.kts settings.gradle settings.gradle.kts).freeze

      PROPERTY_REGEX =
        /
          (?:\$\{property\((?<property_name>[^:\s]*?)\)\})|
          (?:\$\{(?<property_name>[^:\s]*?)\})|
          (?:\$(?<property_name>[^:\s"']*))
        /x

      PART = %r{[^\s,@'":/\\]+}
      VSN_PART = %r{[^\s,'":/\\]+}
      DEPENDENCY_DECLARATION_REGEX = /(?:\(|\s)\s*['"](?<declaration>#{PART}:#{PART}:#{VSN_PART})['"]/

      DEPENDENCY_SET_DECLARATION_REGEX = /(?:^|\s)dependencySet\((?<arguments>[^\)]+)\)\s*\{/
      DEPENDENCY_SET_ENTRY_REGEX = /entry\s+['"](?<name>#{PART})['"]/
      PLUGIN_BLOCK_DECLARATION_REGEX = /(?:^|\s)plugins\s*\{/
      PLUGIN_ID_REGEX = /['"](?<id>#{PART})['"]/

      def parse
        dependency_set = DependencySet.new
        buildfiles.each do |buildfile|
          dependency_set += buildfile_dependencies(buildfile)
        end
        script_plugin_files.each do |plugin_file|
          dependency_set += buildfile_dependencies(plugin_file)
        end
        version_catalog_file.each do |toml_file|
          dependency_set += version_catalog_dependencies(toml_file)
        end
        dependency_set.dependencies
      end

      def self.find_include_names(buildfile)
        return [] unless buildfile

        buildfile.content.
          scan(/apply(\(| )\s*from(\s+=|:)\s+['"]([^'"]+)['"]/).
          map { |match| match[2] }
      end

      def self.find_includes(buildfile, dependency_files)
        FileParser.find_include_names(buildfile).
          filter_map { |f| dependency_files.find { |bf| bf.name == f } }
      end

      private

      def version_catalog_dependencies(toml_file)
        dependency_set = DependencySet.new
        parsed_toml_file = parsed_toml_file(toml_file)
        dependency_set += version_catalog_library_dependencies(parsed_toml_file, toml_file)
        dependency_set += version_catalog_plugin_dependencies(parsed_toml_file, toml_file)
        dependency_set
      end

      def version_catalog_library_dependencies(parsed_toml_file, toml_file)
        dependencies_for_declarations(parsed_toml_file["libraries"], toml_file, :details_for_library_dependency)
      end

      def version_catalog_plugin_dependencies(parsed_toml_file, toml_file)
        dependencies_for_declarations(parsed_toml_file["plugins"], toml_file, :details_for_plugin_dependency)
      end

      def dependencies_for_declarations(declarations, toml_file, details_getter)
        dependency_set = DependencySet.new
        return dependency_set unless declarations

        declarations.each do |_mod, declaration|
          group, name, version = send(details_getter, declaration)

          # Only support basic version and reference formats for now,
          # refrain from updating anything else as it's likely to be a very deliberate choice.
          next unless Gradle::Version.correct?(version) || (version.is_a?(Hash) && version.key?("ref"))

          version_details = Gradle::Version.correct?(version) ? version : "$" + version["ref"]
          details = { group: group, name: name, version: version_details }
          dependency = dependency_from(details_hash: details, buildfile: toml_file)
          next unless dependency

          dependency_set << dependency
        end
        dependency_set
      end

      def details_for_library_dependency(declaration)
        return declaration.split(":") if declaration.is_a?(String)

        if declaration["module"]
          [*declaration["module"].split(":"), declaration["version"]]
        else
          [declaration["group"], declaration["name"], declaration["version"]]
        end
      end

      def details_for_plugin_dependency(declaration)
        return ["plugins", *declaration.split(":")] if declaration.is_a?(String)

        ["plugins", declaration["id"], declaration["version"]]
      end

      def parsed_toml_file(file)
        TomlRB.parse(file.content)
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def map_value_regex(key)
        /(?:^|\s|,|\()#{Regexp.quote(key)}(\s*=|:)\s*['"](?<value>[^'"]+)['"]/
      end

      def buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new

        dependency_set += shortform_buildfile_dependencies(buildfile)
        dependency_set += keyword_arg_buildfile_dependencies(buildfile)
        dependency_set += dependency_set_dependencies(buildfile)
        dependency_set += plugin_dependencies(buildfile)

        dependency_set
      end

      def shortform_buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new

        prepared_content(buildfile).scan(DEPENDENCY_DECLARATION_REGEX) do
          declaration = Regexp.last_match.named_captures.fetch("declaration")

          group, name, version = declaration.split(":")
          version, _packaging_type = version.split("@")
          details = { group: group, name: name, version: version }

          dep = dependency_from(details_hash: details, buildfile: buildfile)
          dependency_set << dep if dep
        end

        dependency_set
      end

      def keyword_arg_buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new

        prepared_content(buildfile).lines.each do |line|
          name    = argument_from_string(line, "name")
          group   = argument_from_string(line, "group")
          version = argument_from_string(line, "version")
          next unless name && group && version

          details = { name: name, group: group, version: version }

          dep = dependency_from(details_hash: details, buildfile: buildfile)
          dependency_set << dep if dep
        end

        dependency_set
      end

      def dependency_set_dependencies(buildfile)
        dependency_set = DependencySet.new

        dependency_set_blocks = []

        prepared_content(buildfile).scan(DEPENDENCY_SET_DECLARATION_REGEX) do
          mch = Regexp.last_match
          dependency_set_blocks <<
            {
              arguments: mch.named_captures.fetch("arguments"),
              block: mch.post_match[0..closing_bracket_index(mch.post_match)]
            }
        end

        dependency_set_blocks.each do |blk|
          group   = argument_from_string(blk[:arguments], "group")
          version = argument_from_string(blk[:arguments], "version")

          next unless group && version

          blk[:block].scan(DEPENDENCY_SET_ENTRY_REGEX).flatten.each do |name|
            dep = dependency_from(
              details_hash: { group: group, name: name, version: version },
              buildfile: buildfile,
              in_dependency_set: true
            )
            dependency_set << dep if dep
          end
        end

        dependency_set
      end

      def plugin_dependencies(buildfile)
        dependency_set = DependencySet.new

        plugin_blocks = []

        prepared_content(buildfile).scan(PLUGIN_BLOCK_DECLARATION_REGEX) do
          mch = Regexp.last_match
          plugin_blocks <<
            mch.post_match[0..closing_bracket_index(mch.post_match)]
        end

        plugin_blocks.each do |blk|
          blk.lines.each do |line|
            name_regex = /(id|kotlin)(\s+#{PLUGIN_ID_REGEX}|\(#{PLUGIN_ID_REGEX}\))/o
            name = line.match(name_regex)&.named_captures&.fetch("id")
            version_regex = /version\s+['"]?(?<version>#{VSN_PART})['"]?/o
            version = format_plugin_version(line.match(version_regex)&.named_captures&.fetch("version"))
            next unless name && version

            details = { name: name, group: "plugins", extra_groups: extra_groups(line), version: version }
            dep = dependency_from(details_hash: details, buildfile: buildfile)
            dependency_set << dep if dep
          end
        end

        dependency_set
      end

      def format_plugin_version(version)
        version&.match?(/^\w+$/) ? "$#{version}" : version
      end

      def extra_groups(line)
        line.match?(/kotlin(\s+#{PLUGIN_ID_REGEX}|\(#{PLUGIN_ID_REGEX}\))/o) ? ["kotlin"] : []
      end

      def argument_from_string(string, arg_name)
        string.
          match(map_value_regex(arg_name))&.
          named_captures&.
          fetch("value")
      end

      def dependency_from(details_hash:, buildfile:, in_dependency_set: false)
        group   = evaluated_value(details_hash[:group], buildfile)
        name    = evaluated_value(details_hash[:name], buildfile)
        version = evaluated_value(details_hash[:version], buildfile)
        extra_groups = details_hash[:extra_groups] || []

        dependency_name =
          if group == "plugins" then name
          else
            "#{group}:#{name}"
          end
        groups =
          if group == "plugins" then ["plugins"] + extra_groups
          else
            []
          end
        source =
          source_from(group, name, version)

        # If we can't evaluate a property they we won't be able to
        # update this dependency
        return if "#{dependency_name}:#{version}".match?(PROPERTY_REGEX)
        return unless Gradle::Version.correct?(version)

        Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            requirement: version,
            file: buildfile.name,
            source: source,
            groups: groups,
            metadata: dependency_metadata(details_hash, in_dependency_set)
          }],
          package_manager: "gradle"
        )
      end

      def source_from(group, name, version)
        return nil unless group&.start_with?("com.github") && version.match?(/\A[0-9a-f]{40}\Z/)

        account = group.sub("com.github.", "")

        {
          type: "git",
          url: "https://github.com/#{account}/#{name}",
          branch: nil,
          ref: version
        }
      end

      def dependency_metadata(details_hash, in_dependency_set)
        version_property_name =
          details_hash[:version].
          match(PROPERTY_REGEX)&.
          named_captures&.fetch("property_name")

        return unless version_property_name || in_dependency_set

        metadata = {}
        metadata[:property_name] = version_property_name if version_property_name
        if in_dependency_set
          metadata[:dependency_set] = {
            group: details_hash[:group],
            version: details_hash[:version]
          }
        end
        metadata
      end

      def evaluated_value(value, buildfile)
        return value unless value.scan(PROPERTY_REGEX).count == 1

        property_name  = value.match(PROPERTY_REGEX).
                         named_captures.fetch("property_name")
        property_value = property_value_finder.property_value(
          property_name: property_name,
          callsite_buildfile: buildfile
        )

        return value unless property_value

        value.gsub(PROPERTY_REGEX, property_value)
      end

      def property_value_finder
        @property_value_finder ||=
          PropertyValueFinder.new(dependency_files: dependency_files)
      end

      def prepared_content(buildfile)
        # Remove any comments
        prepared_content =
          buildfile.content.
          gsub(%r{(?<=^|\s)//.*$}, "\n").
          gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")

        # Remove the dependencyVerification section added by Gradle Witness
        # (TODO: Support updating this in the FileUpdater)
        prepared_content.dup.scan(/dependencyVerification\s*{/) do
          mtch = Regexp.last_match
          block = mtch.post_match[0..closing_bracket_index(mtch.post_match)]
          prepared_content.gsub!(block, "")
        end

        prepared_content
      end

      def closing_bracket_index(string)
        closes_required = 1

        string.chars.each_with_index do |char, index|
          closes_required += 1 if char == "{"
          closes_required -= 1 if char == "}"
          return index if closes_required.zero?
        end

        0
      end

      def buildfiles
        @buildfiles ||= dependency_files.select do |f|
          f.name.end_with?(*SUPPORTED_BUILD_FILE_NAMES)
        end
      end

      def version_catalog_file
        @version_catalog_file ||= dependency_files.select do |f|
          f.name.end_with?("libs.versions.toml")
        end
      end

      def script_plugin_files
        @script_plugin_files ||=
          buildfiles.flat_map do |buildfile|
            FileParser.find_includes(buildfile, dependency_files)
          end.
          uniq
      end

      def check_required_files
        raise "No build.gradle or build.gradle.kts!" if dependency_files.empty?
      end

      def original_file
        dependency_files.find do |f|
          SUPPORTED_BUILD_FILE_NAMES.include?(f.name)
        end
      end
    end
  end
end

Dependabot::FileParsers.register("gradle", Dependabot::Gradle::FileParser)
