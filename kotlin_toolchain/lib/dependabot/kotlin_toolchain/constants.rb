# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module KotlinToolchain
    ECOSYSTEM = "kotlin_toolchain"
    PACKAGE_MANAGER = "kotlin-toolchain"

    UNIX_WRAPPER = "kotlin"
    WINDOWS_WRAPPER = "kotlin.bat"
    WRAPPER_FILES = T.let([UNIX_WRAPPER, WINDOWS_WRAPPER].freeze, T::Array[String])

    PROJECT_FILE = "project.yaml"
    MODULE_FILE = "module.yaml"
    MODULE_TEMPLATE_SUFFIX = ".module-template.yaml"
    VERSION_CATALOG_PATHS = ["libs.versions.toml", "gradle/libs.versions.toml"].freeze

    WRAPPER_DEPENDENCY_NAME = "org.jetbrains.kotlin:kotlin-cli"
    DEFAULT_DISTRIBUTION_REPOSITORY = "https://packages.jetbrains.team/maven/p/amper/amper"
    COMPOSE_HOT_RELOAD_REPOSITORY = "https://packages.jetbrains.team/maven/p/amper/compose-hot-reload"
    KOTLIN_TOOLCHAIN_GITHUB_URL = "https://github.com/JetBrains/kotlin-toolchain"
  end
end
