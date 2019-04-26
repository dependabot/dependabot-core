# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Terraform do
  it_behaves_like "it registers the required classes", "terraform"
end
