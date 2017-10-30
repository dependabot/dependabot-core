# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/java/maven"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven do
  it_behaves_like "an update checker"
end
