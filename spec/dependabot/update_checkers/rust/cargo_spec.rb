# frozen_string_literal: true

require "dependabot/update_checkers/rust/cargo"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Rust::Cargo do
  it_behaves_like "an update checker"
end
