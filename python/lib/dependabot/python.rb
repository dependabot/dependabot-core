# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/python/file_fetcher"
require "dependabot/python/file_parser"
require "dependabot/python/update_checker"
require "dependabot/python/file_updater"
require "dependabot/python/metadata_finder"
require "dependabot/python/requirement"
require "dependabot/python/version"
