# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::RustToolchain do
  it_behaves_like "it registers the required classes", "rust_toolchain"
end
