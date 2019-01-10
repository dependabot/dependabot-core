# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/composer/file_fetcher"
require "dependabot/composer/file_parser"
require "dependabot/composer/update_checker"
require "dependabot/composer/file_updater"
require "dependabot/composer/metadata_finder"
require "dependabot/composer/requirement"
require "dependabot/composer/version"
