# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Bun::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  it_behaves_like "a dependency metadata finder"
end
