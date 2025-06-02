# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Vcpkg do
  it_behaves_like "it registers the required classes", "vcpkg"
end
