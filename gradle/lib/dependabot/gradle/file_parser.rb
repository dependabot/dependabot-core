# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/ecosystem"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/gradle/version"
require "dependabot/gradle/language"
require "dependabot/gradle/package_manager"

# The best Gradle documentation is at:
# - https://docs.gradle.org/current/dsl/org.gradle.api.artifacts.dsl.
#   DependencyHandler.html
#
# In addition, documentation on plugins is at:
# - https://docs.gradle.org/current/userguide/plugins.html
module Dependabot
  module Gradle
    class FileParser < Dependabot::FileParsers::Base # rubocop:disable Metrics/ClassLength
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/distributions_finder.rb"
      require_relative "file_parser/property_value_finder"

      SUPPORTED_BUILD_FILE_NAMES = T.let(
        %w(build.gradle build.gradle.kts settings.gradle settings.gradle.kts).freeze,
        T::Array[String]
      )

      PROPERTY_REGEX = T.let(
        /
          (?:\$\{property\((?<property_name>[^:\s]*?)\)\})|
          (?:\$\{(?<property_name>[^:\s]*?)\})|
          (?:\$(?<property_name>[^:\s"']*))
        /x,
        Regexp
      )

      PART = T.let(%r{[^\s,@'":/\\]+}, Regexp)
      VSN_PART = T.let(%r{[^\s,'":/\\]+}, Regexp)
      DEPENDENCY_DECLARATION_REGEX = T.let(/(?:\(|\s)\s*['"](?<declaration>#{PART}:#{PART}:#{VSN_PART})['"]/o, Regexp)

      DEPENDENCY_SET_DECLARATION_REGEX = T.let(/(?:^|\s)dependencySet\((?<arguments>[^\)]+)\)\s*\{/, Regexp)
      DEPENDENCY_SET_ENTRY_REGEX = T.let(/entry\s+['"](?<name>#{PART})['"]/o, Regexp)
      PLUGIN_BLOCK_DECLARATION_REGEX = T.let(/(?:^|\s)plugins\s*\{/, Regexp)
      PLUGIN_ID_REGEX = T.let(/['"](?<id>#{PART})['"]/o, Regexp)

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        buildfiles.each do |buildfile|
          dependency_set += buildfile_dependencies(buildfile)
        end
        script_plugin_files.each do |plugin_file|
          dependency_set += buildfile_dependencies(plugin_file)
        end
        wrapper_properties_file.each do |properties_file|
          dependency_set += wrapper_properties_dependencies(properties_file)
        end
        version_catalog_file.each do |toml_file|
          dependency_set += version_catalog_dependencies(toml_file)
        end
        dependency_set.dependencies.reject do |dependency|
          dependency.version == "latest.integration" || dependency.version == "latest.release"
        end
      end

      sig { params(buildfile: T.nilable(Dependabot::DependencyFile)).returns(T::Array[String]) }
      def self.find_include_names(buildfile)
        return [] unless buildfile

        T.must(buildfile.content)
         .scan(/apply(\(| )\s*from(\s+=|:)\s+['"]([^'"]+)['"]/)
         .map { |match| T.must(match[2]) }
      end

      sig do
        params(
          buildfile: Dependabot::DependencyFile,
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def self.find_includes(buildfile, dependency_files)
        FileParser.find_include_names(buildfile)
                  .filter_map { |f| dependency_files.find { |bf| bf.name == f } }
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new("NOT-AVAILABLE"),
          T.nilable(Dependabot::Gradle::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          begin
            Language.new("NOT-AVAILABLE")
          end,
          T.nilable(Dependabot::Gradle::Language)
        )
      end

      sig { params(properties_file: Dependabot::DependencyFile).returns(DependencySet) }
      def wrapper_properties_dependencies(properties_file)
        dependency_set = DependencySet.new
        dependency = DistributionsFinder.resolve_dependency(properties_file)
        dependency_set << dependency if dependency
        dependency_set
      end

      sig { params(toml_file: Dependabot::DependencyFile).returns(DependencySet) }
      def version_catalog_dependencies(toml_file)
        dependency_set = DependencySet.new
        parsed_toml_file = parsed_toml_file(toml_file)
        dependency_set += version_catalog_library_dependencies(parsed_toml_file, toml_file)
        dependency_set += version_catalog_plugin_dependencies(parsed_toml_file, toml_file)
        dependency_set
      end

      sig do
        params(
          parsed_toml_file: T::Hash[String, T.untyped],
          toml_file: Dependabot::DependencyFile
        ).returns(DependencySet)
      end
      def version_catalog_library_dependencies(parsed_toml_file, toml_file)
        dependencies_for_declarations(
          T.cast(parsed_toml_file["libraries"], T.nilable(T::Hash[String, T.any(String, T::Hash[String, String])])),
          toml_file,
          :details_for_library_dependency
        )
      end

      sig do
        params(
          parsed_toml_file: T::Hash[String, T.untyped],
          toml_file: Dependabot::DependencyFile
        ).returns(DependencySet)
      end
      def version_catalog_plugin_dependencies(parsed_toml_file, toml_file)
        dependencies_for_declarations(
          T.cast(parsed_toml_file["plugins"], T.nilable(T::Hash[String, T.any(String, T::Hash[String, String])])),
          toml_file,
          :details_for_plugin_dependency
        )
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig do
        params(
          declarations: T.nilable(T::Hash[String, T.any(String, T::Hash[String, String])]),
          toml_file: Dependabot::DependencyFile,
          details_getter: Symbol
        ).returns(DependencySet)
      end
      def dependencies_for_declarations(declarations, toml_file, details_getter)
        dependency_set = DependencySet.new
        return dependency_set unless declarations

        declarations.each do |_mod, declaration|
          details = send(details_getter, declaration)
          next unless details

          group, name, version = T.cast(
            details,
            [String, String, T.any(String, T::Hash[String, String])]
          )

          # Only support basic version and reference formats for now,
          # refrain from updating anything else as it's likely to be a very deliberate choice.
          next unless Gradle::Version.correct?(version) || (version.is_a?(Hash) && version.key?("ref"))

          if version.is_a?(Hash)
            version_details = "$" + T.must(version["ref"])
          elsif Gradle::Version.correct?(version)
            version_details = version
          else
            raise ArgumentError, "Unexpected version format: #{version.inspect}"
          end
          details = T.let({ group: group, name: name, version: version_details }, T::Hash[Symbol, String])
          dependency = dependency_from(details_hash: details, buildfile: toml_file)
          next unless dependency

          dependency_set << dependency
        end
        dependency_set
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig do
        params(
          declaration: T.any(String, T::Hash[String, T.any(String, T::Hash[String, String])])
        ).returns(T.nilable([String, String, T.any(String, T::Hash[String, String])]))
      end
      def details_for_library_dependency(declaration)
        return T.cast(declaration.split(":"), [String, String, String]) if declaration.is_a?(String)

        hash = declaration
        version = hash["version"]
        return nil if version.nil?

        if hash["module"]
          parts = T.cast(hash["module"], String).split(":")
          [T.must(parts[0]), T.must(parts[1]), version]
        else
          [T.cast(hash["group"], String), T.cast(hash["name"], String), version]
        end
      end

      sig do
        params(declaration: T.any(String, T::Hash[String, String]))
          .returns(T.nilable([String, String, T.any(String, T::Hash[String, String])]))
      end
      def details_for_plugin_dependency(declaration)
        if declaration.is_a?(String)
          parts = declaration.split(":")
          ["plugins", T.must(parts[0]), T.must(parts[1])]
        else
          decl_hash = declaration
          version = decl_hash["version"]
          return nil if version.nil?

          ["plugins", T.must(decl_hash["id"]), version]
        end
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, T.untyped]) }
      def parsed_toml_file(file)
        T.cast(TomlRB.parse(file.content), T::Hash[String, T.untyped])
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(key: String).returns(Regexp) }
      def map_value_regex(key)
        /(?:^|\s|,|\()#{Regexp.quote(key)}(\s*=|:)\s*['"](?<value>[^'"]+)['"]/
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new

        dependency_set += shortform_buildfile_dependencies(buildfile)
        dependency_set += keyword_arg_buildfile_dependencies(buildfile)
        dependency_set += dependency_set_dependencies(buildfile)
        dependency_set += plugin_dependencies(buildfile)

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def shortform_buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new

        prepared_content(buildfile).scan(DEPENDENCY_DECLARATION_REGEX) do
          declaration = T.must(Regexp.last_match).named_captures.fetch("declaration")

          group, name, version = T.must(declaration).split(":")
          version, _packaging_type = T.must(version).split("@")
          details = { group: group, name: name, version: version }

          dep = dependency_from(details_hash: details, buildfile: buildfile)
          dependency_set << dep if dep
        end

        dependency_set
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
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

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def dependency_set_dependencies(buildfile)
        dependency_set = DependencySet.new

        dependency_set_blocks = T.let([], T::Array[T::Hash[Symbol, String]])

        prepared_content(buildfile).scan(DEPENDENCY_SET_DECLARATION_REGEX) do
          mch = T.must(Regexp.last_match)
          dependency_set_blocks <<
            {
              arguments: mch.named_captures.fetch("arguments"),
              block: mch.post_match[0..closing_bracket_index(mch.post_match)]
            }
        end

        dependency_set_blocks.each do |blk|
          arguments = T.must(blk[:arguments])
          group   = argument_from_string(arguments, "group")
          version = argument_from_string(arguments, "version")

          next unless group && version

          T.must(blk[:block]).scan(DEPENDENCY_SET_ENTRY_REGEX).flatten.each do |name|
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

      sig { params(buildfile: Dependabot::DependencyFile).returns(DependencySet) }
      def plugin_dependencies(buildfile)
        dependency_set = DependencySet.new

        plugin_blocks = T.let([], T::Array[String])

        prepared_content(buildfile).scan(PLUGIN_BLOCK_DECLARATION_REGEX) do
          mch = T.must(Regexp.last_match)
          post_match_str = mch.post_match
          plugin_blocks <<
            T.must(post_match_str.slice(0..closing_bracket_index(mch.post_match)))
        end

        plugin_blocks.each do |blk|
          blk.lines.each do |line|
            name_regex = /(id|kotlin)(\s+#{PLUGIN_ID_REGEX}|\(#{PLUGIN_ID_REGEX}\))/o
            name = line.match(name_regex)&.named_captures&.fetch("id")
            version_regex = /version\s+(?<version>['"]?#{VSN_PART}['"]?)/o
            version = format_plugin_version(line.match(version_regex)&.named_captures&.fetch("version"))
            next unless name && version

            details = { name: name, group: "plugins", extra_groups: extra_groups(line), version: version }
            dep = dependency_from(details_hash: details, buildfile: buildfile)
            dependency_set << dep if dep
          end
        end

        dependency_set
      end

      sig { params(version: T.nilable(String)).returns(T.nilable(String)) }
      def format_plugin_version(version)
        return nil unless version

        quoted?(version) ? unquote(version) : "$#{version}"
      end

      sig { params(line: String).returns(T::Array[String]) }
      def extra_groups(line)
        line.match?(/kotlin(\s+#{PLUGIN_ID_REGEX}|\(#{PLUGIN_ID_REGEX}\))/o) ? ["kotlin"] : []
      end

      sig { params(string: String, arg_name: String).returns(T.nilable(String)) }
      def argument_from_string(string, arg_name)
        string
          .match(map_value_regex(arg_name))
          &.named_captures
          &.fetch("value")
      end

      sig do
        params(
          details_hash: T::Hash[Symbol, T.any(String, T::Array[String])],
          buildfile: Dependabot::DependencyFile,
          in_dependency_set: T::Boolean
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def dependency_from(details_hash:, buildfile:, in_dependency_set: false) # rubocop:disable Metrics/PerceivedComplexity
        group   = evaluated_value(T.cast(details_hash[:group], T.nilable(String)), buildfile)
        name    = evaluated_value(T.cast(details_hash[:name], T.nilable(String)), buildfile)
        version = evaluated_value(T.cast(details_hash[:version], T.nilable(String)), buildfile)
        extra_groups = T.cast(details_hash[:extra_groups], T.nilable(T::Array[String])) || []

        return nil unless group && name && version

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

      sig do
        params(
          group: String,
          name: String,
          version: String
        ).returns(T.nilable(T::Hash[Symbol, T.nilable(String)]))
      end
      def source_from(group, name, version)
        return nil unless group.start_with?("com.github") && version.match?(/\A[0-9a-f]{40}\Z/)

        account = group.sub("com.github.", "")

        {
          type: "git",
          url: "https://github.com/#{account}/#{name}",
          branch: nil,
          ref: version
        }
      end

      sig do
        params(
          details_hash: T::Hash[Symbol, T.any(String, T::Array[String])],
          in_dependency_set: T::Boolean
        ).returns(T.nilable(T::Hash[Symbol, T.any(String, T::Hash[Symbol, String])]))
      end
      def dependency_metadata(details_hash, in_dependency_set)
        version_property_name =
          T.cast(details_hash[:version], String)
           .match(PROPERTY_REGEX)
           &.named_captures&.fetch("property_name")

        return unless version_property_name || in_dependency_set

        metadata = T.let({}, T::Hash[Symbol, T.any(String, T::Hash[Symbol, String])])
        metadata[:property_name] = version_property_name if version_property_name
        if in_dependency_set
          metadata[:dependency_set] = T.let(
            {
              group: details_hash[:group],
              version: details_hash[:version]
            },
            T::Hash[Symbol, String]
          )
        end
        metadata
      end

      sig { params(value: T.nilable(String), buildfile: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def evaluated_value(value, buildfile)
        return value unless value&.scan(PROPERTY_REGEX)&.one?

        property_name = T.must(
          T.must(value).match(PROPERTY_REGEX)
                                    &.named_captures&.fetch("property_name")
        )
        property_value = property_value_finder.property_value(
          property_name: property_name,
          callsite_buildfile: buildfile
        )

        return value unless property_value

        T.must(value).gsub(PROPERTY_REGEX, property_value)
      end

      sig { returns(PropertyValueFinder) }
      def property_value_finder
        @property_value_finder ||= T.let(
          PropertyValueFinder.new(dependency_files: dependency_files),
          T.nilable(PropertyValueFinder)
        )
      end

      sig { params(buildfile: Dependabot::DependencyFile).returns(String) }
      def prepared_content(buildfile)
        # Remove any comments
        prepared_content =
          T.must(buildfile.content)
           .gsub(%r{(?<=^|\s)//.*$}, "\n")
           .gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")

        # Remove the dependencyVerification section added by Gradle Witness
        # (TODO: Support updating this in the FileUpdater)
        prepared_content.dup.scan(/dependencyVerification\s*{/) do
          mtch = T.must(Regexp.last_match)
          block = mtch.post_match[0..closing_bracket_index(mtch.post_match)]
          prepared_content.gsub!(T.must(block), "")
        end

        prepared_content
      end

      sig { params(string: String).returns(Integer) }
      def closing_bracket_index(string)
        closes_required = 1

        string.chars.each_with_index do |char, index|
          closes_required += 1 if char == "{"
          closes_required -= 1 if char == "}"
          return index if closes_required.zero?
        end

        0
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def buildfiles
        @buildfiles ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def wrapper_properties_file
        @wrapper_properties_file ||= T.let(
          dependency_files.select { |f| f.name.end_with?("gradle-wrapper.properties") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def version_catalog_file
        @version_catalog_file ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("libs.versions.toml")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def script_plugin_files
        @script_plugin_files ||= T.let(
          buildfiles.flat_map do |buildfile|
            FileParser.find_includes(buildfile, dependency_files)
          end
                    .uniq,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        raise "No build.gradle or build.gradle.kts!" if dependency_files.empty?
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def original_file
        dependency_files.find do |f|
          SUPPORTED_BUILD_FILE_NAMES.include?(f.name)
        end
      end

      sig { params(string: String).returns(T::Boolean) }
      def quoted?(string)
        string.match?(/^['"].*['"]$/) || false
      end

      sig { params(string: String).returns(String) }
      def unquote(string)
        T.must(string[1..-2])
      end
    end
  end
end

Dependabot::FileParsers.register("gradle", Dependabot::Gradle::FileParser)
