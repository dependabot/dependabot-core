# frozen_string_literal: true

require "dependabot/update_checkers/go/dep"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Go::Dep do
  it_behaves_like "an update checker"
end
