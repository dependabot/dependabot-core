# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/bitbucket_with_retries"

RSpec.describe Dependabot::Clients::BitbucketWithRetries do
  let(:client) { described_class.new(credentials: nil, max_retries: 1) }
  let(:bitbucket_client) { client.__getobj__ }

  it "retries delegated methods with fresh argument copies" do
    attempts = 0
    statuses = ["OPEN"]

    allow(bitbucket_client).to receive(:pull_requests) do |_repo, _source, _target, received_statuses|
      attempts += 1
      received_statuses << "MUTATED"
      raise Excon::Error::Timeout if attempts == 1

      received_statuses
    end

    result = client.pull_requests("owner/repo", "source", "target", statuses)

    expect(result).to eq(%w(OPEN MUTATED))
    expect(statuses).to eq(["OPEN"])
    expect(attempts).to eq(2)
  end

  it "reports delegated methods as supported" do
    expect(client).to respond_to(:pull_requests)
  end
end
