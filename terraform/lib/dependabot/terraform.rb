# frozen_string_literal: true

# These all need to be required as the register various classes against a
# lookup table of package manager names to concrete classes.
#
# TODO: in due course, these registrations shouldn't be necessary for
#       dependabot-core to function, and the "registries" should live in a
#       wrapper gem, not dependabot-core.
require "dependabot/terraform/requirement"
require "dependabot/terraform/version"
require "dependabot/terraform/metadata_finder"
