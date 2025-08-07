# typed: strict
# frozen_string_literal: true

# These files are part of the Dependabot Core library, which provides
# functionality for managing dependencies across various ecosystems.
# This file specifically handles the NuGet package management system.
require "dependabot/nuget/requirement"
require "dependabot/nuget/version"

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "nuget",
  lambda do |groups|
    return true if groups.empty?

    groups.include?("dependencies")
  end
)
