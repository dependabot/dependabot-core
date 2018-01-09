# frozen_string_literal: true

require "dependabot/update_checkers/c_sharp/nuget"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::CSharp::Nuget do
  it_behaves_like "an update checker"
end
