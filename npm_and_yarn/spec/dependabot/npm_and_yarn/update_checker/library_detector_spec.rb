# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/npm_and_yarn/library_detector"

tested_module = Dependabot::UpdateCheckers::JavaScript::NpmAndYarn
RSpec.describe tested_module::LibraryDetector do
  subject(:finder) { described_class.new(package_json_file: package_json_file) }
  let(:package_json_file) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("javascript", "package_files", package_json_fixture_name)
    )
  end
  let(:package_json_fixture_name) { "package.json" }

  describe "library?" do
    subject { finder.library? }

    context "with private set to true" do
      let(:package_json_fixture_name) { "workspaces.json" }
      it { is_expected.to eq(false) }
    end

    context "with no version" do
      let(:package_json_fixture_name) { "app_no_version.json" }
      it { is_expected.to eq(false) }
    end

    context "with {{ }} in the name" do
      let(:package_json_fixture_name) { "package.json" }
      it { is_expected.to eq(false) }
    end

    context "with a library package.json" do
      let(:package_json_fixture_name) { "etag.json" }

      context "not listed on npm" do
        before do
          stub_request(:get, "https://registry.npmjs.org/etag").
            to_return(status: 404)
        end

        it { is_expected.to eq(false) }
      end

      context "listed on npm" do
        before do
          stub_request(:get, "https://registry.npmjs.org/etag").
            to_return(status: 200, body: body)
        end

        context "with a description that matches" do
          let(:body) { fixture("javascript", "npm_responses", "etag.json") }
          it { is_expected.to eq(true) }
        end

        context "with a description that doesn't match" do
          let(:body) do
            fixture("javascript", "npm_responses", "is_number.json")
          end
          it { is_expected.to eq(false) }
        end
      end
    end
  end
end
