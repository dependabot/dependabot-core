# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/java_script"

RSpec.describe Bump::UpdateCheckers::JavaScript do
  before do
    stub_request(:get, "http://registry.npmjs.org/etag").
      to_return(status: 200, body: fixture("npm_response.json"))
  end

  let(:checker) do
    described_class.new(dependency: dependency, dependency_files: [])
  end

  let(:dependency) do
    Bump::Dependency.new(name: "etag", version: "1.0.0", language: "javascript")
  end

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:dependency) do
        Bump::Dependency.new(
          name: "etag",
          version: "1.7.0",
          language: "javascript"
        )
      end

      it { is_expected.to be_falsey }
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "http://registry.npmjs.org/@blep%2Fblep").
          to_return(status: 200, body: fixture("npm_response.json"))
      end
      let(:dependency) do
        Bump::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          language: "javascript"
        )
      end
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq("1.7.0") }

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "http://registry.npmjs.org/eTag" }

      before do
        stub_request(:get, "http://registry.npmjs.org/etag").
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: fixture("npm_response.json"))
      end

      it { is_expected.to eq("1.7.0") }
    end
  end
end
