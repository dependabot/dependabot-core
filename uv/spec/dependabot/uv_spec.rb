# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/uv"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Uv do
  it_behaves_like "it registers the required classes", "uv"
end
