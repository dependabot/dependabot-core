# frozen_string_literal: true

require "spec_helper"
require "dependabot/cake"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Cake do
  it_behaves_like "it registers the required classes", "cake"
end
