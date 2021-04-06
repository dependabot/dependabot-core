# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Pub do
  it_behaves_like "it registers the required classes", "pub"
end
