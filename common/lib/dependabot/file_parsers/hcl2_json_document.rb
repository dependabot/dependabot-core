# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/errors"

module Dependabot
  module FileParsers
    class Hcl2JsonDocument
      extend T::Sig

      ObjectHash = T.type_alias { T::Hash[String, Object] }
      ModuleBlocks = T.type_alias { T::Hash[String, T::Array[ObjectHash]] }

      class Declaration
        extend T::Sig

        sig { params(name: String, fields: ObjectHash, path: String).void }
        def initialize(name:, fields:, path:)
          @name = name
          @fields = fields
          @path = path
        end

        sig { returns(String) }
        attr_reader :name

        sig { returns(T.nilable(String)) }
        def version
          optional_string("version")
        end

        protected

        sig { params(key: String).returns(String) }
        def string(key)
          value = @fields[key]
          return value if value.is_a?(String)

          raise DependencyFileNotParseable.new(@path, "#{@name}.#{key} must be a string")
        end

        sig { params(key: String).returns(T.nilable(String)) }
        def optional_string(key)
          string(key) unless @fields[key].nil?
        end
      end

      class ModuleDeclaration < Declaration
        extend T::Sig

        sig { returns(String) }
        def source
          string("source")
        end
      end

      class ProviderDeclaration < Declaration
        extend T::Sig

        sig { returns(T.nilable(String)) }
        def source
          optional_string("source")
        end
      end

      class DeprecatedProvider < T::ImmutableStruct
        const :name, String
      end

      Provider = T.type_alias { T.any(ProviderDeclaration, DeprecatedProvider) }

      sig { params(output: String, file: DependencyFile).returns(Hcl2JsonDocument) }
      def self.from_helper_output(output, file:)
        new(T.cast(JSON.parse(output), Object), file.path)
      rescue JSON::ParserError => e
        raise DependencyFileNotParseable.new(file.path, e.message)
      end

      sig { params(data: Object, path: String).void }
      def initialize(data, path)
        @path = path
        @data = T.let(object(data, "root"), ObjectHash)
      end

      sig { params(overrides: T::Array[Hcl2JsonDocument]).returns(T::Array[ModuleDeclaration]) }
      def module_declarations(overrides: [])
        modules = module_blocks
        overrides.each { |override| modules = merge_modules(override.module_blocks, modules) }
        modules.map do |name, entries|
          fields = entries.first
          invalid!("module.#{name} must contain a block") unless fields

          ModuleDeclaration.new(name: name, fields: fields, path: @path)
        end
      end

      sig { returns(T::Array[Provider]) }
      def provider_declarations
        blocks("terraform").flat_map { |block| providers_for(block) }
      end

      sig { returns(T::Array[String]) }
      def terragrunt_sources
        blocks("terraform").filter_map do |block|
          value = block["source"]
          next unless value

          invalid!("terraform.source must be a string") unless value.is_a?(String)
          value
        end
      end

      sig { returns(T::Hash[String, String]) }
      def local_strings
        blocks("locals").each_with_object(T.let({}, T::Hash[String, String])) do |block, result|
          block.each { |name, value| result[name] = value if value.is_a?(String) }
        end
      end

      sig { params(source: String).returns(T.nilable(String)) }
      def provider_version(source)
        value = @data["provider"]
        return if value.nil?

        entries = object(value, "provider")[source]
        return if entries.nil?

        entry = array(entries, "provider.#{source}").first
        return if entry.nil?

        version = object(entry, "provider.#{source}")["version"]
        return if version.nil?

        invalid!("provider.#{source}.version must be a string") unless version.is_a?(String)
        version
      end

      protected

      sig { returns(ModuleBlocks) }
      def module_blocks
        object(@data.fetch("module", {}), "module").to_h do |name, entries|
          [name, array(entries, "module.#{name}").map { |entry| object(entry, "module.#{name}") }]
        end
      end

      private

      sig { params(overrides: ModuleBlocks, base: ModuleBlocks).returns(ModuleBlocks) }
      def merge_modules(overrides, base)
        merged = base.dup
        overrides.each do |name, entries|
          existing = merged[name]
          merged[name] = if existing
                           fields = entries.first
                           invalid!("module.#{name} override must contain a block") unless fields

                           existing.map { |entry| entry.merge(fields) }
                         else
                           entries
                         end
        end
        merged
      end

      sig { params(block: ObjectHash).returns(T::Array[Provider]) }
      def providers_for(block)
        array(block.fetch("required_providers", []), "terraform.required_providers").flat_map do |group|
          object(group, "required_providers").map do |name, value|
            if value.is_a?(String)
              DeprecatedProvider.new(name: name)
            else
              ProviderDeclaration.new(name: name, fields: object(value, "provider.#{name}"), path: @path)
            end
          end
        end
      end

      sig { params(key: String).returns(T::Array[ObjectHash]) }
      def blocks(key)
        array(@data.fetch(key, []), key).map { |entry| object(entry, key) }
      end

      sig { params(value: Object, field: String).returns(ObjectHash) }
      def object(value, field)
        invalid!("#{field} must be an object") unless value.is_a?(Hash)

        T.let(value, ObjectHash)
      end

      sig { params(value: Object, field: String).returns(T::Array[Object]) }
      def array(value, field)
        invalid!("#{field} must be an array") unless value.is_a?(Array)

        value.map { |entry| T.cast(entry, Object) }
      end

      sig { params(message: String).returns(T.noreturn) }
      def invalid!(message)
        raise DependencyFileNotParseable.new(@path, message)
      end
    end
  end
end
