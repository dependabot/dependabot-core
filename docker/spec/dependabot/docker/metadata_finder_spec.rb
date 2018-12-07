# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Docker::MetadataFinder do
  it_behaves_like "a dependency metadata finder"
end
