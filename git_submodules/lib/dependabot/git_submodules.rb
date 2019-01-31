# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/git_submodules/file_fetcher"
require "dependabot/git_submodules/file_parser"
require "dependabot/git_submodules/update_checker"
require "dependabot/git_submodules/file_updater"
require "dependabot/git_submodules/metadata_finder"
require "dependabot/git_submodules/requirement"
