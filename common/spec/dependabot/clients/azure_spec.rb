# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/azure"

RSpec.describe Dependabot::Clients::Azure do
  let(:username) { "username" }
  let(:password) { "password" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "dev.azure.com",
      "username" => username,
      "password" => password
    }]
  end
  let(:branch) { "master" }
  let(:base_url) { "https://dev.azure.com/org/gocardless" }
  let(:repo_url) { base_url + "/_apis/git/repositories/gocardless" }
  let(:branch_url) { repo_url + "/stats/branches?name=" + branch }
  let(:source) { Dependabot::Source.from_url(base_url + "/_git/gocardless") }
  let(:client) do
    described_class.for_source(source: source, credentials: credentials)
  end

  describe ".fetch_commit" do
    subject { client.fetch_commit(nil, branch) }

    context "when response is 200" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 200, body: fixture("azure", "master_branch.json"))
      end

      specify { expect { subject }.to_not raise_error }

      it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }
    end

    context "when response is 404" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end
  end
end
