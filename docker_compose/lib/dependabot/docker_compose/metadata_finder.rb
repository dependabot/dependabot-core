# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/docker/metadata_finder"

Dependabot::MetadataFinders
  .register("docker_compose", Dependabot::Docker::MetadataFinder)
