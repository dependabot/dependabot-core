# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Bazel
    class ExtensionRegistry
      extend T::Sig

      class ExtensionInfo < T::Struct
        const :ecosystem, String
        const :tag_parsers, T::Hash[String, Symbol]
      end

      EXTENSION_MAP = T.let(
        {
          # Go Modules via bazel-gazelle
          "go_deps" => ExtensionInfo.new(
            ecosystem: "go_modules",
            tag_parsers: {
              "module" => :parse_go_module_tag
            }
          ),
          # Maven via rules_jvm_external
          "maven" => ExtensionInfo.new(
            ecosystem: "maven",
            tag_parsers: {
              "artifact" => :parse_maven_artifact_tag,
              "install" => :parse_maven_install_tag
            }
          ),
          # Rust/Cargo via rules_rust
          "crate" => ExtensionInfo.new(
            ecosystem: "cargo",
            tag_parsers: {
              "spec" => :parse_cargo_spec_tag
            }
          )
        }.freeze,
        T::Hash[String, ExtensionInfo]
      )

      sig { params(extension_name: String).returns(T.nilable(String)) }
      def self.ecosystem_for(extension_name)
        info = EXTENSION_MAP[extension_name]
        info&.ecosystem
      end

      sig { params(extension_name: String, tag_name: String).returns(T.nilable(Symbol)) }
      def self.tag_parser_for(extension_name, tag_name)
        info = EXTENSION_MAP[extension_name]
        return nil unless info

        info.tag_parsers[tag_name]
      end

      sig { params(extension_name: String).returns(T::Boolean) }
      def self.supported?(extension_name)
        EXTENSION_MAP.key?(extension_name)
      end

      sig { returns(T::Array[String]) }
      def self.supported_extensions
        EXTENSION_MAP.keys
      end

      sig { returns(T::Array[String]) }
      def self.supported_ecosystems
        EXTENSION_MAP.values.map(&:ecosystem).uniq
      end
    end
  end
end
