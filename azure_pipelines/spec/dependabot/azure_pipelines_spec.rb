# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/azure_pipelines"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::AzurePipelines do
  it_behaves_like "it registers the required classes", "azure_pipelines"
end
