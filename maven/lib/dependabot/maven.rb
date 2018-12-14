# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/maven/file_fetcher"
require "dependabot/maven/file_parser"
require "dependabot/maven/update_checker"
require "dependabot/maven/file_updater"
require "dependabot/maven/metadata_finder"
require "dependabot/maven/requirement"
require "dependabot/maven/version"
