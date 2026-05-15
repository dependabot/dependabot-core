# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Nix do
  it_behaves_like "it registers the required classes", "nix"
end
