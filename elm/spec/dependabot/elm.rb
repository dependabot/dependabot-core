# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/elm/file_fetcher"
require "dependabot/elm/file_parser"
require "dependabot/elm/update_checker"
require "dependabot/elm/file_updater"
require "dependabot/elm/metadata_finder"
require "dependabot/elm/requirement"
require "dependabot/elm/version"
