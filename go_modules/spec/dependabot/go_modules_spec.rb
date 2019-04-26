# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::GoModules do
  it_behaves_like "it registers the required classes", "go_modules"
end
