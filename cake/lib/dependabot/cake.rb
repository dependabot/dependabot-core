# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/cake/file_fetcher"
require "dependabot/cake/file_parser"
require "dependabot/cake/file_updater"
