# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Lein::UpdateChecker do
  it_behaves_like "an update checker"
end
