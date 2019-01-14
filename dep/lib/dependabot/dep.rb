# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/dep/file_fetcher"
require "dependabot/dep/file_parser"
require "dependabot/dep/update_checker"
require "dependabot/dep/file_updater"
require "dependabot/dep/metadata_finder"
require "dependabot/dep/requirement"
require "dependabot/dep/version"
