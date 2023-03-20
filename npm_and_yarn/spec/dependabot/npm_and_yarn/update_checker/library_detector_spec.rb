# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/library_detector"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::LibraryDetector do
  subject(:finder) do
    described_class.new(
      package_json_file: package_json_file,
      credentials: credentials,
      dependency_files: dependency_files
    )
  end
  let(:package_json_file) do
    project_dependency_files(project_name).find { |f| f.name == "package.json" }
  end
  let(:credentials) { {} }
  let(:dependency_files) { project_dependency_files(project_name) }

  describe "library?" do
    subject { finder.library? }

    context "with private set to true" do
      let(:project_name) { "npm8/workspaces" }
      it { is_expected.to eq(false) }
    end

    context "with no version" do
      let(:project_name) { "npm8/app_no_version" }
      it { is_expected.to eq(false) }
    end

    context "with {{ }} in the name" do
      let(:project_name) { "npm8/simple" }
      it { is_expected.to eq(false) }
    end

    context "with space in the name" do
      let(:project_name) { "npm8/package_with_space_in_name" }
      it { is_expected.to eq(false) }
    end

    context "with a library package.json" do
      let(:project_name) { "npm8/library" }

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
          let(:body) { fixture("npm_responses", "etag.json") }
          it { is_expected.to eq(true) }
        end

        context "with a description that doesn't match" do
          let(:body) do
            fixture("npm_responses", "is_number.json")
          end
          it { is_expected.to eq(false) }
        end
      end
    end

    context "with a custom global registry" do
      let(:project_name) { "npm8/library_with_global_registry" }

      context "not listed in registry" do
        before do
          stub_request(:get, "http://example.com/dependabot/etag").
            to_return(status: 404)
        end

        it { is_expected.to eq(false) }
      end

      context "listed on registry" do
        before do
          stub_request(:get, "http://example.com/dependabot/etag").
            to_return(status: 200, body: body)
        end

        context "with a description that matches" do
          let(:body) { fixture("npm_responses", "etag.json") }
          it { is_expected.to eq(true) }
        end

        context "with a description that doesn't match" do
          let(:body) do
            fixture("npm_responses", "is_number.json")
          end
          it { is_expected.to eq(false) }
        end
      end
    end

    context "with a custom scoped registry" do
      let(:project_name) { "npm8/library_with_scoped_registry" }

      context "not listed in registry" do
        before do
          stub_request(:get, "http://example.com/dependabot/@dependabot%2Fetag").
            to_return(status: 404)
        end

        it { is_expected.to eq(false) }
      end

      context "listed on registry" do
        before do
          stub_request(:get, "http://example.com/dependabot/@dependabot%2Fetag").
            to_return(status: 200, body: body)
        end

        context "with a description that matches" do
          let(:body) { fixture("npm_responses", "etag.json") }
          it { is_expected.to eq(true) }
        end

        context "with a description that doesn't match" do
          let(:body) do
            fixture("npm_responses", "is_number.json")
          end
          it { is_expected.to eq(false) }
        end
      end
    end
  end
end
