# frozen_string_literal: true

require "dependabot/file_updaters/rust/cargo"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Rust::Cargo do
  it_behaves_like "a dependency file updater"
end
