# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/version"

module Dependabot
  module KotlinToolchain
    class CompatibilityProfile
      extend T::Sig

      BuiltIn = T.type_alias { T::Hash[Symbol, T.any(String, T::Array[String])] }

      BASE_BUILT_INS = T.let(
        [
          {
            path: %w(kotlin version),
            dependency: "org.jetbrains.kotlin:kotlin-stdlib"
          },
          {
            path: %w(compose version),
            dependency: "org.jetbrains.compose.runtime:runtime"
          },
          {
            path: %w(compose experimental hotReload version),
            dependency: "org.jetbrains.compose.hot-reload:hot-reload-runtime-api",
            repository: COMPOSE_HOT_RELOAD_REPOSITORY
          },
          {
            path: %w(jvm test junitPlatformVersion),
            dependency: "org.junit.platform:junit-platform-console-standalone"
          },
          {
            path: %w(kotlin serialization version),
            dependency: "org.jetbrains.kotlinx:kotlinx-serialization-core"
          },
          {
            path: %w(kotlin rpc version),
            dependency: "org.jetbrains.kotlinx:kotlinx-rpc-bom"
          },
          {
            path: %w(kotlin ksp version),
            dependency: "com.google.devtools.ksp:symbol-processing-api"
          },
          {
            path: %w(ktor version),
            dependency: "io.ktor:ktor-bom"
          },
          {
            path: %w(lombok version),
            dependency: "org.projectlombok:lombok"
          },
          {
            path: %w(springBoot version),
            dependency: "org.springframework.boot:spring-boot-dependencies"
          }
        ].freeze,
        T::Array[BuiltIn]
      )

      DATAFRAME_BUILT_IN = T.let(
        {
          path: %w(kotlin dataframe version),
          dependency: "org.jetbrains.kotlinx:dataframe-core"
        }.freeze,
        BuiltIn
      )

      sig do
        params(
          name: String,
          built_ins: T::Array[BuiltIn],
          nested_templates: T::Boolean,
          fallback: T::Boolean
        ).void
      end
      def initialize(name:, built_ins:, nested_templates:, fallback: false)
        @name = name
        @built_ins = built_ins
        @nested_templates = nested_templates
        @fallback = fallback
      end

      sig { returns(String) }
      attr_reader :name

      sig { returns(T::Array[BuiltIn]) }
      attr_reader :built_ins

      sig { returns(T::Boolean) }
      def nested_templates?
        @nested_templates
      end

      sig { returns(T::Boolean) }
      def fallback?
        @fallback
      end

      sig { params(raw_version: String).returns(CompatibilityProfile) }
      def self.for(raw_version)
        case raw_version
        when /\A0\.11(?:\z|[.-])/
          new(name: "0.11", built_ins: BASE_BUILT_INS, nested_templates: false)
        when /\A0\.12(?:\z|[.-])/
          new(
            name: "0.12",
            built_ins: BASE_BUILT_INS + [DATAFRAME_BUILT_IN],
            nested_templates: true
          )
        else
          version = Version.new(raw_version)
          if version < Version.new("0.11.0")
            new(name: "legacy", built_ins: [], nested_templates: false, fallback: true)
          else
            new(
              name: "future",
              built_ins: BASE_BUILT_INS + [DATAFRAME_BUILT_IN],
              nested_templates: true,
              fallback: true
            )
          end
        end
      end
    end
  end
end
