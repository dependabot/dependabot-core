require "spec_helper"
require "bumper/dependency"
require "bumper/update_checker/update_checker"

RSpec.describe UpdateChecker::RubyUpdateChecker do
  let(:outdated_dependency) { fixture("out_of_date_dependency_response.json") }
  let(:outdated_dependency_json) { JSON.parse(outdated_dependency) }
  let(:outdated_dependency_url) do
    "https://rubygems.org/api/v1/gems/#{outdated_dependency_json["name"]}.json"
  end

  let(:latest_dependency) { fixture("up_to_date_dependency_response.json") }
  let(:latest_dependency_json) { JSON.parse(latest_dependency) }
  let(:latest_dependency_url) do
    "https://rubygems.org/api/v1/gems/#{latest_dependency_json["name"]}.json"
  end

  before do
    stub_request(:get, outdated_dependency_url).
      to_return(status: 200, body: outdated_dependency, headers: {})

    stub_request(:get, latest_dependency_url).
      to_return(status: 200, body: latest_dependency, headers: {})
  end

  let(:initial_dependencies) do
    [
      Dependency.new(
        name: latest_dependency_json["name"],
        version: latest_dependency_json["version"]
      ),
      Dependency.new(
        name: outdated_dependency_json["name"],
        version: "1.2.0"
      )
    ]
  end

  let(:checker) { UpdateChecker::RubyUpdateChecker.new(initial_dependencies) }
  subject(:dependencies) { checker.outdated_dependencies }

  its(:length) { is_expected.to eq(1) }

  describe "the only dependency" do
    subject { dependencies.first }

    it { is_expected.to be_a(Dependency) }
    its(:name) { is_expected.to eq(outdated_dependency_json["name"]) }
    its(:version) { is_expected.to eq("1.2.0") }
  end

end
