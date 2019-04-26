# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_submodules"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::GitSubmodules do
  it_behaves_like "it registers the required classes", "submodules"
end
