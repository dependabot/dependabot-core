# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::DotnetSdk do
  it_behaves_like "it registers the required classes", "dotnet_sdk"
end
