# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Hex do
  it_behaves_like "it registers the required classes", "hex"
end
