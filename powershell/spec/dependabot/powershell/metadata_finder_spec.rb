# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/powershell/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Powershell::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Az.Storage",
      version: "1.0.0",
      requirements: [{
        file: "MyModule.psd1",
        requirement: "1.0.0",
        groups: [],
        source: nil
      }],
      package_manager: "powershell"
    )
  end

  describe "#source_url" do
    # PowerShell Gallery modules have no reliable, structured way to derive
    # a GitHub source URL from manifest metadata alone, so look_up_source is
    # currently a stub that always returns nil.
    it "returns nil" do
      expect(finder.source_url).to be_nil
    end
  end
end
