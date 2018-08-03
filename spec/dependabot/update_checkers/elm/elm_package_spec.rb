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
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end
  let(:dependency_files) { [elm_package] }
  let(:github_token) { "token" }
  let(:directory) { "/" }
  let(:credentials) { nil }
  let(:ignored_versions) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "elm-package"
    )
  end
  let(:dependency_name) { "realWorld/ElmPackage" }
  let(:dependency_version) { "2.2.0" }
  let(:requirements) do
    [{
      file: "elm-package.json",
      requirement: string_req,
      groups: [],
      source: nil
    }]
  end
  let(:string_req) { "1.0.0 <= v <= 2.2.0" }

  let(:elm_package) do
    Dependabot::DependencyFile.new(
      content: fixture("elm", "elm_package", fixture_name),
      name: "Gemfile",
      directory: directory
    )
  end
  let(:fixture_name) { "for_update_checking" }

  describe "up_to_date?" do
    subject { checker.up_to_date? }

    context "with a requirement that is out of date, but needs a full unlock" do
      let(:fixture_name) { "elm_css_and_datetimepicker_ranges" }
      let(:dependency_name) { "NoRedInk/datetimepicker" }
      let(:string_req) { "3.0.0 <= v <= 3.0.1" }
      let(:dependency_version) { nil }
      let(:elm_package_url) do
        "http://package.elm-lang.org/packages/NoRedInk/datetimepicker/"
      end
      let(:elm_package_response) do
        fixture("elm", "elm_package_responses", "NoRedInk-datetimepicker.html")
      end

      before do
        stub_request(:get, elm_package_url).
          to_return(status: 200, body: elm_package_response)
      end

      it { is_expected.to eq(false) }
    end
  end

  describe "can_update?" do
    subject { checker.can_update?(requirements_to_unlock: unlock_level) }
    let(:unlock_level) { :own }

    context "with a version that is out of date, but needs a full unlock" do
      let(:fixture_name) { "elm_css_and_datetimepicker_ranges" }
      let(:dependency_name) { "NoRedInk/datetimepicker" }
      let(:string_req) { "3.0.1 <= v <= 3.0.1" }
      let(:dependency_version) { "3.0.1" }
      let(:elm_package_url) do
        "http://package.elm-lang.org/packages/NoRedInk/datetimepicker/"
      end
      let(:elm_package_response) do
        fixture("elm", "elm_package_responses", "NoRedInk-datetimepicker.html")
      end
      let(:unlock_level) { :all }

      before do
        stub_request(:get, elm_package_url).
          to_return(status: 200, body: elm_package_response)
      end

      it { is_expected.to eq(true) }
    end

    context "with a requirement that is out of date, but needs a full unlock" do
      let(:fixture_name) { "elm_css_and_datetimepicker_ranges" }
      let(:dependency_name) { "NoRedInk/datetimepicker" }
      let(:string_req) { "3.0.0 <= v <= 3.0.1" }
      let(:dependency_version) { nil }
      let(:elm_package_url) do
        "http://package.elm-lang.org/packages/NoRedInk/datetimepicker/"
      end
      let(:elm_package_response) do
        fixture("elm", "elm_package_responses", "NoRedInk-datetimepicker.html")
      end
      let(:unlock_level) { :all }

      before do
        stub_request(:get, elm_package_url).
          to_return(status: 200, body: elm_package_response)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:elm_package_url) do
      "http://package.elm-lang.org/packages/realWorld/ElmPackage/"
    end
    let(:elm_package_response) do
      fixture("elm", "elm_package_responses", "elm-lang-core.html")
    end

    before do
      stub_request(:get, elm_package_url).
        to_return(status: 200, body: elm_package_response)
    end

    it { is_expected.to eq(Dependabot::Utils::Elm::Version.new("5.1.1")) }

    context "when the registry 404s" do
      before { stub_request(:get, elm_package_url).to_return(status: 404) }
      it { is_expected.to be_nil }
    end

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 5.0.0"] }
      it { is_expected.to eq(Dependabot::Utils::Elm::Version.new("4.0.5")) }
    end
  end
end
