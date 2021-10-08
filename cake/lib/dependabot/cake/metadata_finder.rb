# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/nuget/metadata_finder"

Dependabot::MetadataFinders.register("cake", Dependabot::Nuget::MetadataFinder)
