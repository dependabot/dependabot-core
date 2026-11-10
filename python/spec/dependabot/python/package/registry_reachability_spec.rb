# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/package/registry_reachability"

RSpec.describe Dependabot::Python::Package::RegistryReachability do
  let(:url) { "https://pypi.org/simple/" }

  before { described_class.clear_cache! }

  after { described_class.clear_cache! }

  describe ".reachable?" do
    subject(:reachable) { described_class.reachable?(url) }

    context "when the registry answers" do
      before { stub_request(:head, url).to_return(status: 200) }

      it { is_expected.to be(true) }
    end

    # Any response means the network path works, whatever the registry thinks of the request
    [404, 429, 503].each do |status|
      context "when the registry answers with status #{status}" do
        before { stub_request(:head, url).to_return(status: status) }

        it { is_expected.to be(true) }
      end
    end

    context "when the connection is closed without a response" do
      before do
        stub_request(:head, url).to_raise(Excon::Error::Socket.new(EOFError.new("end of file reached")))
      end

      it { is_expected.to be(false) }

      it "asks once, without Excon's retries" do
        reachable

        expect(a_request(:head, url)).to have_been_made.once
      end
    end

    context "when the request times out" do
      before { stub_request(:head, url).to_raise(Excon::Error::Timeout.new("read timeout reached")) }

      it { is_expected.to be(false) }
    end

    context "when the registry cannot be reached and is asked about again" do
      before do
        stub_request(:head, url).to_raise(Excon::Error::Socket.new(EOFError.new("end of file reached")))
      end

      it "remembers that it cannot be reached, so a blocked runner is not asked once per dependency" do
        3.times { described_class.reachable?(url) }

        expect(a_request(:head, url)).to have_been_made.once
      end

      it "asks again after the cache is cleared" do
        described_class.reachable?(url)
        described_class.clear_cache!
        described_class.reachable?(url)

        expect(a_request(:head, url)).to have_been_made.twice
      end
    end

    context "when the registry answered and is asked about again" do
      before { stub_request(:head, url).to_return(status: 200) }

      it "asks every time, because a later failure is not explained by an earlier answer" do
        2.times { described_class.reachable?(url) }

        expect(a_request(:head, url)).to have_been_made.twice
      end
    end

    context "when the registry becomes reachable after it was not" do
      before do
        stub_request(:head, url)
          .to_raise(Excon::Error::Socket.new(EOFError.new("end of file reached"))).then
          .to_return(status: 200)
      end

      it "does not trust the earlier answer once the cache is cleared" do
        expect(described_class.reachable?(url)).to be(false)
        described_class.clear_cache!
        expect(described_class.reachable?(url)).to be(true)
      end
    end
  end
end
