# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/package/npm_package_json"
require "dependabot/npm_and_yarn/requirement"

module Dependabot
  module NpmAndYarn
    # Catalog definitions own the editable ranges; manifests retain their references.
    class YarnCatalogs
      extend T::Sig

      require "dependabot/npm_and_yarn/file_parser/yarn_lock"

      SUPPORTED_GROUPS = %w(dependencies devDependencies).freeze
      OTHER_LOCKFILES = %w(package-lock.json npm-shrinkwrap.json pnpm-lock.yaml).freeze

      # Yarn uses js-yaml's failsafe schema: even unquoted scalar keys and
      # values are strings. Decode the syntax tree without Psych's coercions.
      sig { params(content: String).returns(T::Hash[String, Object]) }
      def self.parse_configuration(content)
        documents = YAML.parse_stream(content.delete_prefix("\uFEFF")).children
        raise DependencyFileNotParseable.new(".yarnrc.yml", "expected a single YAML document") unless documents.one?

        root = documents.first&.children&.first
        parsed = root && decode_node(root, {})
        raise DependencyFileNotParseable.new(".yarnrc.yml", "expected a mapping") unless parsed.is_a?(Hash)

        parsed
      rescue Psych::Exception => e
        raise DependencyFileNotParseable.new(".yarnrc.yml", e.message)
      end

      sig { params(node: Psych::Nodes::Node, anchors: T::Hash[String, Object]).returns(Object) }
      def self.decode_node(node, anchors)
        validate_tag!(node)

        value = case node
                when Psych::Nodes::Scalar then node.value
                when Psych::Nodes::Sequence
                  node.children.map { |child| decode_node(child, anchors) }
                when Psych::Nodes::Mapping
                  node.children.each_slice(2).with_object({}) do |(key, child), result|
                    unless key.is_a?(Psych::Nodes::Scalar)
                      raise DependencyFileNotParseable.new(".yarnrc.yml", "expected scalar mapping keys")
                    end

                    key_value = T.cast(decode_node(key, anchors), String)
                    result[key_value] = decode_node(child, anchors)
                  end
                when Psych::Nodes::Alias
                  anchors.fetch(node.anchor) { raise Psych::BadAlias, "Unknown or recursive alias: #{node.anchor}" }
                else
                  raise DependencyFileNotParseable.new(".yarnrc.yml", "unsupported configuration node")
                end
        anchors[node.anchor] = value if node.respond_to?(:anchor) && node.anchor
        value
      end
      private_class_method :decode_node

      sig { params(node: Psych::Nodes::Node).void }
      def self.validate_tag!(node)
        return unless node.respond_to?(:tag) && node.tag

        expected = case node
                   when Psych::Nodes::Scalar then "tag:yaml.org,2002:str"
                   when Psych::Nodes::Sequence then "tag:yaml.org,2002:seq"
                   when Psych::Nodes::Mapping then "tag:yaml.org,2002:map"
                   end
        return if node.tag == expected

        raise DependencyFileNotParseable.new(".yarnrc.yml", "unsupported configuration tag: #{node.tag}")
      end
      private_class_method :validate_tag!

      class Binding < T::Struct
        const :name, String
        const :reference, String
        const :requirement, String
        const :groups, T::Array[String]
      end

      sig { params(dependency_files: T::Array[DependencyFile]).void }
      def initialize(dependency_files:)
        @dependency_files = dependency_files
        @bindings = T.let(nil, T.nilable(T::Array[Binding]))
        @configuration = T.let(nil, T.nilable(T::Hash[String, Object]))
        @yarn_project = T.let(nil, T.nilable(T::Boolean))
        @lockfile_reader = T.let(nil, T.nilable(FileParser::YarnLock))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def config_file
        @dependency_files.find { |file| file.name == ".yarnrc.yml" } ||
          @dependency_files.find { |file| file.name.end_with?("/.yarnrc.yml") }
      end

      sig { returns(T::Array[Binding]) }
      def bindings
        return @bindings if @bindings
        return @bindings = [] unless yarn_project?

        entries = T.let({}, T::Hash[[String, String], Binding])
        manifest_files.each do |file|
          Dependabot::Package::NpmPackageJson.from_file(file).each_dependency do |name, reference, group|
            next unless reference.start_with?("catalog:")

            key = [name, reference]
            binding = entries[key] ||= Binding.new(
              name: name, reference: reference, requirement: resolve(name, reference), groups: []
            )
            binding.groups << group unless binding.groups.include?(group)
          end
        end
        @bindings = entries.values
      end

      sig { returns(T::Boolean) }
      def yarn_project?
        return @yarn_project unless @yarn_project.nil?

        root = @dependency_files.find { |file| file.name == "package.json" }
        pin = root && Dependabot::Package::NpmPackageJson.from_file(root).package_manager_config.package_manager
        return @yarn_project = pin.start_with?("yarn@") if pin

        @yarn_project = @dependency_files.any? { |file| file.name.end_with?("yarn.lock") } &&
                        @dependency_files.none? do |file|
                          OTHER_LOCKFILES.include?(file.name) || file.name == "pnpm-workspace.yaml"
                        end
      end

      sig { params(name: String, reference: String).returns(String) }
      def resolve(name, reference)
        catalog_name = reference.delete_prefix("catalog:")
        named = configuration["catalogs"]
        catalog = if catalog_name.empty?
                    configuration["catalog"]
                  else
                    named.is_a?(Hash) ? named[catalog_name] : nil
                  end
        requirement = catalog.is_a?(Hash) ? catalog[name] : nil
        return requirement if requirement.is_a?(String) && !requirement.empty?

        raise DependencyFileNotResolvable, "#{name}@#{reference}: catalog entry missing from .yarnrc.yml"
      end

      sig { returns(T::Hash[String, T::Hash[String, String]]) }
      def helper_catalogs
        bindings.each_with_object({}) do |binding, result|
          result[binding.reference] ||= {}
          result[binding.reference][binding.name] = binding.requirement
        end
      end

      sig { params(binding: Binding).returns(T.nilable(Dependabot::Package::NpmLockfileDetails)) }
      def lockfile_details(binding)
        lock = @dependency_files.find { |file| file.name.end_with?("yarn.lock") }
        return unless lock

        @lockfile_reader ||= FileParser::YarnLock.new(lock)
        @lockfile_reader.details(binding.name, binding.requirement, ".yarnrc.yml", strict: true)
      end

      sig { params(binding: Binding).returns(T::Boolean) }
      def workspace_dependency?(binding)
        lockfile_details(binding)&.resolution&.start_with?("#{binding.name}@workspace:") || false
      end

      sig { params(name: String).void }
      def validate_update!(name)
        selected = bindings.select { |binding| binding.name == name }
        return if selected.empty?

        unsupported!(name, "multiple catalog bindings") unless selected.one?
        unsupported!(name, "catalog and ordinary direct requirements") if ordinary_requirement?(name)
        binding = T.must(selected.first)
        unsupported_groups = binding.groups - SUPPORTED_GROUPS
        unsupported!(name, "catalog requirements in #{unsupported_groups.join(', ')}") if unsupported_groups.any?
        unsupported!(name, "non-registry catalog requirements") unless registry_requirement?(binding.requirement)
        validate_project!(name)
        unsupported!(name, "catalog resolves to a local workspace") if workspace_dependency?(binding)
      end

      sig { params(requirement: String).returns(T::Boolean) }
      def registry_requirement?(requirement)
        return false if Version::VERSION_TAGS.include?(requirement.strip)
        return false if requirement.include?(":")

        Requirement.requirements_array(requirement).any?
      rescue Gem::Requirement::BadRequirementError
        false
      end

      sig { params(version: String).void }
      def validate_yarn_version!(version)
        return if Version.new(version.strip) >= Version.new("4.10.0")

        raise ToolFeatureNotSupported.new(tool_name: "yarn", tool_type: "package_manager", feature: "native catalogs")
      end

      private

      sig { params(name: String).void }
      def validate_project!(name)
        unless (%w(package.json yarn.lock .yarnrc.yml) - @dependency_files.map(&:name)).empty?
          unsupported!(name, "catalog configuration outside the Yarn project root")
        end
        if @dependency_files.any? { |file| OTHER_LOCKFILES.include?(file.name) || file.name == "pnpm-workspace.yaml" }
          unsupported!(name, "multiple package manager projects")
        end
      end

      sig { returns(T::Array[DependencyFile]) }
      def manifest_files
        @dependency_files.select { |file| file.name.end_with?("package.json") && !file.support_file? }
                         .sort_by(&:name)
      end

      sig { returns(T::Hash[String, Object]) }
      def configuration
        return @configuration if @configuration

        unless config_file&.content
          raise DependencyFileNotResolvable, "Yarn catalog configuration missing from .yarnrc.yml"
        end

        @configuration = self.class.parse_configuration(T.must(config_file&.content))
      end

      sig { params(name: String).returns(T::Boolean) }
      def ordinary_requirement?(name)
        manifest_files.any? do |file|
          found = T.let(false, T::Boolean)
          Dependabot::Package::NpmPackageJson.from_file(file).each_dependency do |package, requirement, _group|
            found = true if package == name && !requirement.start_with?("catalog:")
          end
          found
        end
      end

      sig { params(name: String, feature: String).returns(T.noreturn) }
      def unsupported!(name, feature)
        raise ToolFeatureNotSupported.new(
          tool_name: "yarn",
          tool_type: "package_manager",
          feature: "#{name}: #{feature}"
        )
      end
    end
  end
end
