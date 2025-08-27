# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Type definitions for repository file structures
module Dependabot
  module Uv
    extend T::Sig

    # Hash representing a path dependency
    PathDependency = T.type_alias { T::Hash[Symbol, String] }

    # Hash representing TOML content
    TomlContent = T.type_alias { T::Hash[String, T.untyped] }
  end
end

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/uv/file_fetcher"
require "dependabot/uv/file_parser"
require "dependabot/uv/update_checker"
require "dependabot/uv/file_updater"
require "dependabot/uv/metadata_finder"
require "dependabot/uv/requirement"
require "dependabot/uv/version"
require "dependabot/uv/name_normaliser"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("uv", name: "python:uv", colour: "2b67c6")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "uv",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("default")
    return true if groups.include?("install_requires")

    groups.include?("dependencies")
  end
)

# See https://www.python.org/dev/peps/pep-0503/#normalized-names
Dependabot::Dependency.register_name_normaliser(
  "uv",
  ->(name) { Dependabot::Uv::NameNormaliser.normalise(name) }
)
