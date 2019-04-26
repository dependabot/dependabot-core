# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Composer do
  it_behaves_like "it registers the required classes", "composer"
end
