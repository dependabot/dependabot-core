# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Swift do
  it_behaves_like "it registers the required classes", "swift"
end
