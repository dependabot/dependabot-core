# frozen_string_literal: true

require "dependabot/metadata_finders/go/dep"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Go::Dep do
  it_behaves_like "a dependency metadata finder"
end
