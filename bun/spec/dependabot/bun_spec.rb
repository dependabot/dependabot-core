# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Bun do
  it_behaves_like "it registers the required classes", "bun"
end
