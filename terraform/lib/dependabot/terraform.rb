# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/terraform/file_fetcher"
require "dependabot/terraform/file_parser"
require "dependabot/terraform/update_checker"
require "dependabot/terraform/file_updater"
require "dependabot/terraform/metadata_finder"
require "dependabot/terraform/requirement"
require "dependabot/terraform/version"
