# frozen_string_literal: true

require "spec_helper"
require "dependabot/metadata_finders/docker/docker"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Docker::Docker do
  it_behaves_like "a dependency metadata finder"
end
