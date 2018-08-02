# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/elm/elm_package"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Elm::ElmPackage do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: nil
    )
  end
  let(:dependency_files) { [elm_package] }
  let(:github_token) { "token" }
  let(:directory) { "/" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "elm-package"
    )
  end
  let(:dependency_name) { "realWorld/ElmPackage" }
  let(:current_version) { Dependabot::Utils::Elm::Version.new("2.2.0") }
  let(:requirements) do
    [{ file: "elm-package.json", requirement: "1.0.0 <= v <= 2.2.0",
       groups: [], source: nil }]
  end

  let(:elm_package) do
    Dependabot::DependencyFile.new(
      content: fixture("elm", "elm_package", "for_update_checking"),
      name: "Gemfile",
      directory: directory
    )
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:elm_package_url) do
      "http://package.elm-lang.org/packages/realWorld/ElmPackage/"
    end
    let(:elm_package_response) do
      fixture("elm", "elm_package", "elm-package_response")
    end

    before do
      stub_request(:get, elm_package_url).
        to_return(status: 200, body: elm_package_response)
      allow(checker).to receive(:latest_resolvable_version).
        and_return(Dependabot::Utils::Elm::Version.new("2.1.0"))
    end

    it { is_expected.to eq(Dependabot::Utils::Elm::Version.new("5.1.1")) }

    context "when the registry 404s" do
      before { stub_request(:get, elm_package_url).to_return(status: 404) }
      it { is_expected.to eq(Dependabot::Utils::Elm::Version.new("2.2.0")) }
    end
  end
end
