require "spec_helper"
require "bumper/dependency"
require "bumper/update_checkers/ruby_update_checker"

RSpec.describe UpdateCheckers::RubyUpdateChecker do
  let(:rubygems_response) { fixture("rubygems_response.json") }
  let(:rubygems_response_json) { JSON.parse(rubygems_response) }
  let(:rubygems_url) do
    "https://rubygems.org/api/v1/gems/#{dependency.name}.json"
  end

  before do
    stub_request(:get, rubygems_url).
      to_return(status: 200, body: rubygems_response, headers: {})
  end

  let(:checker) { UpdateCheckers::RubyUpdateChecker.new(dependency) }
  let(:dependency_version) { "1.2.0" }
  let(:dependency) do
    Dependency.new(
      name: rubygems_response_json["name"],
      version: dependency_version,
    )
  end

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an up-to-date dependency" do
      let(:dependency_version) { rubygems_response_json["version"] }
      it { is_expected.to be_falsey }
    end

    context "given an outdated dependency" do
      let(:dependency_version) { "1.2.0" }
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(rubygems_response_json["version"]) }
  end
end
