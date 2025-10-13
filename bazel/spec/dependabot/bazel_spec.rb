# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Bazel do
  it_behaves_like "it registers the required classes", "bazel"
end
