# frozen_string_literal: true

# These all need to be required as the register various classes against a
# lookup table of package manager names to concrete classes.
require "dependabot/terraform/requirement"
require "dependabot/terraform/version"
require "dependabot/terraform/metadata_finder"
