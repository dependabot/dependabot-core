# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget"
require_common_spec "shared_examples_for_autoloading"

time_limit_seconds = 5 * 60 # 5 minutes

RSpec.configure do |config|
  config.around do |example|
    Timeout.timeout(time_limit_seconds) { example.run }
  end
end

RSpec.describe Dependabot::Nuget do
  it_behaves_like "it registers the required classes", "nuget"
end
