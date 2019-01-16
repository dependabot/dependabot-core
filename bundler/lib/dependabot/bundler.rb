# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/bundler/file_fetcher"
require "dependabot/bundler/file_parser"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater"
require "dependabot/bundler/metadata_finder"
require "dependabot/bundler/requirement"
require "dependabot/bundler/version"
