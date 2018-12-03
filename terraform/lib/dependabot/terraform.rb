# frozen_string_literal: true

require "dependabot/terraform/requirement"
require "dependabot/terraform/metadata_finder"

# TODO: in due course, these registrations shouldn't be necessary for
#       dependabot-core to function, and the "registries" should live in a
#       wrapper gem, not dependabot-core.

Dependabot::Utils.
  register_requirement_class("terraform", Dependabot::Terraform::Requirement)

Dependabot::MetadataFinders.
  register("terraform", Dependabot::Terraform::MetadataFinder)
