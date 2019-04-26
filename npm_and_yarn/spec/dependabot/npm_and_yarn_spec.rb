# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::NpmAndYarn do
  it_behaves_like "it registers the required classes", "npm_and_yarn"
end
