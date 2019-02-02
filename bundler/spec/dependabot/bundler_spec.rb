# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Bundler do
  it_behaves_like "it registers the required classes", "bundler"
end
