# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Cargo do
  it_behaves_like "it registers the required classes", "cargo"
end
