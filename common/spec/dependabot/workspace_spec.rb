# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/workspace"

RSpec.describe Dependabot::Workspace do
  specify ".active_workspace" do
    expect(described_class.active_workspace).to be_nil

    workspace = instance_double(Dependabot::Workspace::Git)
    described_class.active_workspace = workspace
    expect(described_class.active_workspace).to eq(workspace)

    described_class.active_workspace = nil
    expect(described_class.active_workspace).to be_nil
  end
end
