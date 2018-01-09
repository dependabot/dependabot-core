# frozen_string_literal: true

require "dependabot/metadata_finders/rust/cargo"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Rust::Cargo do
  it_behaves_like "a dependency metadata finder"
end
