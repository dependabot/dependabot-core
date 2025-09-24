# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/helm"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Helm do
  it_behaves_like "it registers the required classes", "helm"
end
