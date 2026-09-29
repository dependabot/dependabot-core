# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/vcpkg"

module Dependabot
  module Vcpkg
    class ManifestDocument
      extend T::Sig

      ObjectHash = T.type_alias { T::Hash[String, Object] }

      class Port < T::ImmutableStruct
        const :name, String
        const :constraint, T.nilable(String)
      end

      class Registry < T::ImmutableStruct
        const :name, String
        const :baseline, String
        const :repository, String
        const :reference, String
        const :builtin, T::Boolean
      end

      sig { params(file: DependencyFile).returns(ManifestDocument) }
      def self.from_file(file)
        new(file)
      end

      sig { params(file: DependencyFile).void }
      def initialize(file)
        @path = T.let(file.path, String)
        @data = T.let(object(T.cast(JSON.parse(T.must(file.content)), Object), "root"), ObjectHash)
      rescue JSON::ParserError
        raise DependencyFileNotParseable.new(@path, "#{@path}: invalid JSON")
      end

      sig { returns(T.nilable(String)) }
      def builtin_baseline
        value = @data[VCPKG_BUILTIN_BASELINE_KEY]
        return if value.nil?

        string(value, VCPKG_BUILTIN_BASELINE_KEY)
      end

      sig { returns(T::Boolean) }
      def dependencies_declared?
        !array(@data[VCPKG_DEPENDENCIES_KEY], VCPKG_DEPENDENCIES_KEY).empty?
      end

      sig { returns(T::Array[Port]) }
      def ports
        array(@data[VCPKG_DEPENDENCIES_KEY], VCPKG_DEPENDENCIES_KEY).filter_map do |entry|
          case entry
          when String
            Port.new(name: entry, constraint: nil)
          when Hash
            fields = object(entry, "dependency")
            name = fields["name"]
            next unless name.is_a?(String)

            constraint = fields[VCPKG_VERSION_CONSTRAINT_KEY]
            Port.new(name: name, constraint: constraint.is_a?(String) ? constraint : nil)
          else
            Dependabot.logger.warn("Skipping unknown vcpkg dependency format: #{entry.inspect}")
            nil
          end
        end
      end

      sig { returns(T::Boolean) }
      def default_registry_present?
        !default_registry_fields.nil?
      end

      sig { returns(T.nilable(String)) }
      def default_registry_kind
        value = default_registry_fields&.[]("kind")
        value if value.is_a?(String)
      end

      sig { returns(T.nilable(String)) }
      def default_registry_repository
        value = default_registry_fields&.[]("repository")
        value if value.is_a?(String)
      end

      sig { returns(T.nilable(String)) }
      def default_registry_baseline
        value = default_registry_fields&.[]("baseline")
        value if value.is_a?(String)
      end

      sig { returns(T.nilable(Registry)) }
      def default_registry
        fields = default_registry_fields
        registry(fields, "default-registry") if fields
      end

      sig { returns(T::Array[Registry]) }
      def registries
        array(@data["registries"], "registries").each_with_index.filter_map do |entry, index|
          field = "registries[#{index}]"
          registry(object(entry, field), field)
        end
      end

      sig { params(name: String, version: T.nilable(String)).void }
      def set_port_version(name:, version:)
        entries = array(@data[VCPKG_DEPENDENCIES_KEY], VCPKG_DEPENDENCIES_KEY)
        index = entries.index { |entry| port_name(entry) == name }
        return unless index

        entry = entries.fetch(index)
        fields = entry.is_a?(String) ? { "name" => entry } : object(entry, "dependencies[#{index}]")
        fields[VCPKG_VERSION_CONSTRAINT_KEY] = version
        entries[index] = fields
        @data[VCPKG_DEPENDENCIES_KEY] = entries
      end

      # Overrides replace the whole pin so deprecated scheme/port-version fields cannot conflict.
      sig { params(name: String, version: T.nilable(String)).void }
      def set_override(name:, version:)
        overrides = array(@data[VCPKG_OVERRIDES_KEY], VCPKG_OVERRIDES_KEY)
        index = overrides.index { |entry| entry.is_a?(Hash) && port_name(entry) == name }
        entry = { "name" => name, "version" => version }
        index ? overrides[index] = entry : overrides << entry
        @data[VCPKG_OVERRIDES_KEY] = overrides
      end

      sig { params(baseline: String, create: T::Boolean).void }
      def set_default_registry_baseline(baseline:, create:)
        fields = default_registry_fields
        if fields
          fields["baseline"] = baseline
        elsif create
          @data["default-registry"] = {
            "kind" => "git",
            "repository" => VCPKG_DEFAULT_REGISTRY_REPOSITORY,
            "baseline" => baseline
          }
        end
      end

      sig { params(baseline: String, repository: T.nilable(String), builtin: T::Boolean).void }
      def set_registry_baseline(baseline:, repository:, builtin:)
        entries = array(@data["registries"], "registries")
        entries.each_with_index do |entry, index|
          next unless entry.is_a?(Hash)

          fields = object(entry, "registries[#{index}]")
          matches = builtin ? fields["kind"] == "builtin" : fields["repository"] == repository
          next unless matches

          fields["baseline"] = baseline
          break
        end
      end

      sig { params(path: T::Array[String], baseline: String).void }
      def set_baseline(path:, baseline:)
        target = @data
        path[0...-1].to_a.each_with_index do |segment, index|
          target = object(target[segment], path.take(index + 1).join("."))
        end
        target[T.must(path.last)] = baseline
      end

      sig { returns(String) }
      def content
        JSON.pretty_generate(@data)
      end

      private

      sig { returns(T.nilable(ObjectHash)) }
      def default_registry_fields
        value = @data["default-registry"]
        object(value, "default-registry") unless value.nil?
      end

      sig { params(fields: ObjectHash, field: String).returns(T.nilable(Registry)) }
      def registry(fields, field)
        kind = fields["kind"]
        baseline = fields["baseline"]
        return unless VCPKG_SUPPORTED_REGISTRY_TYPES.include?(kind) && baseline.is_a?(String)

        if kind == "builtin"
          Registry.new(
            name: VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME,
            baseline: baseline,
            repository: VCPKG_DEFAULT_BASELINE_URL,
            reference: VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH,
            builtin: true
          )
        else
          repository = fields["repository"]
          return unless repository.is_a?(String)

          Registry.new(
            name: repository,
            baseline: baseline,
            repository: repository,
            reference: string(fields["reference"] || "HEAD", "#{field}.reference"),
            builtin: false
          )
        end
      end

      sig { params(entry: Object).returns(T.nilable(String)) }
      def port_name(entry)
        return entry if entry.is_a?(String)
        return unless entry.is_a?(Hash)

        name = object(entry, "dependency")["name"]
        name if name.is_a?(String)
      end

      sig { params(value: Object, field: String).returns(ObjectHash) }
      def object(value, field)
        invalid(field, "must be an object") unless value.is_a?(Hash)

        value.each_key do |raw_key|
          invalid(field, "keys must be strings") unless T.cast(raw_key, Object).is_a?(String)
        end
        # Keep the parsed node's identity so nested edits reach the serialized document.
        value
      end

      sig { params(value: Object, field: String).returns(T::Array[Object]) }
      def array(value, field)
        return [] if value.nil?

        invalid(field, "must be an array") unless value.is_a?(Array)

        value.map { |entry| T.cast(entry, Object) }
      end

      sig { params(value: Object, field: String).returns(String) }
      def string(value, field)
        return value if value.is_a?(String)

        invalid(field, "must be a string")
      end

      sig { params(field: String, message: String).returns(T.noreturn) }
      def invalid(field, message)
        raise DependencyFileNotParseable.new(@path, "#{@path}: #{field} #{message}")
      end
    end
  end
end
