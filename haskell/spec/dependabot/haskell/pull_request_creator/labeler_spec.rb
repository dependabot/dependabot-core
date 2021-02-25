# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/haskell/pull_request_creator/labeler"

RSpec.describe Dependabot::Haskell::PullRequestCreator::Labeler do
  subject(:labeler) do
    described_class.new(
      source: source,
      credentials: credentials,
      custom_labels: custom_labels,
      includes_security_fixes: includes_security_fixes,
      dependencies: [dependency],
      label_language: label_language,
      automerge_candidate: automerge_candidate
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:custom_labels) { nil }
  let(:includes_security_fixes) { false }
  let(:label_language) { false }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: version,
      previous_version: previous_version,
      package_manager: "dummy",
      requirements: requirements,
      previous_requirements: previous_requirements
    )
  end
  let(:automerge_candidate) { false }

  let(:version) { "1.5.0" }
  let(:previous_version) { "1.4.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end

  describe ".precision" do
    subject { labeler.precision }

    context "PVP regards the difference between 1.5.0 and 1.4.0 as major" do
      it { is_expected.to eq(1) }
    end
  end

end
