# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/registry_client"

RSpec.describe Dependabot::Maven::RegistryClient do
  let(:url) { "https://example.com" }
  let(:maven_defaults) do
    { idempotent: true }
  end
  let(:dependabot_defaults) do
    Dependabot::SharedHelpers.excon_defaults
  end

  before do
    allow(Excon).to receive(:get)
    allow(Excon).to receive(:head)
  end

  describe "delegation to Excon" do
    describe "::get" do
      it "delegates requests using Dependabot defaults" do
        expect(Excon).to receive(:get).with(url, **maven_defaults, **dependabot_defaults)

        described_class.get(url: url)
      end

      it "delegates headers correctly" do
        headers = { "Foo" => "Bar" }
        expect(Excon).to receive(:get).with(url, **maven_defaults, **dependabot_defaults.merge(headers: {
          "Foo" => "Bar",
          "User-Agent" => anything
        }))

        described_class.get(url: url, headers: headers)
      end

      it "delegates options correctly" do
        options = { foo: "bar" }
        expect(Excon).to receive(:get).with(url, **maven_defaults, **dependabot_defaults.merge(options))

        described_class.get(url: url, options: options)
      end

      it "delegates with headers and options merged correctly" do
        headers = { "Foo" => "Bar" }
        options = { bar: "baaz" }
        expect(Excon).to receive(:get).with(url, **maven_defaults, **dependabot_defaults.merge(
          headers: {
            "Foo" => "Bar",
            "User-Agent" => anything
          },
          bar: "baaz"
        ))

        described_class.get(url: url, headers: headers, options: options)
      end

      it "ignores headers that are passed as options" do
        headers = { "Foo" => "Bar" }
        options = { headers: headers }
        expect(Excon).to receive(:get).with(url, **maven_defaults, **dependabot_defaults.merge(headers: {
          "Foo" => "Bar",
          "User-Agent" => anything
        }))

        described_class.get(url: url, options: options)
      end
    end

    describe "::head" do
      it "delegates requests using Dependabot defaults" do
        expect(Excon).to receive(:head).with(url, **maven_defaults, **dependabot_defaults)

        described_class.head(url: url)
      end

      it "delegates headers correctly" do
        headers = { "Foo" => "Bar" }
        expect(Excon).to receive(:head).with(url, **maven_defaults, **dependabot_defaults.merge(headers: {
          "Foo" => "Bar",
          "User-Agent" => anything
        }))

        described_class.head(url: url, headers: headers)
      end

      it "delegates options correctly" do
        options = { foo: "bar" }
        expect(Excon).to receive(:head).with(url, **maven_defaults, **dependabot_defaults.merge(options))

        described_class.head(url: url, options: options)
      end

      it "delegates with headers and options merged correctly" do
        headers = { "Foo" => "Bar" }
        options = { bar: "baaz" }
        expect(Excon).to receive(:head).with(url, **maven_defaults, **dependabot_defaults.merge(
          headers: {
            "Foo" => "Bar",
            "User-Agent" => anything
          },
          bar: "baaz"
        ))

        described_class.head(url: url, headers: headers, options: options)
      end

      it "ignores headers that are passed as options" do
        headers = { "Foo" => "Bar" }
        options = { headers: headers }
        expect(Excon).to receive(:head).with(url, **maven_defaults, **dependabot_defaults.merge(headers: {
          "Foo" => "Bar",
          "User-Agent" => anything
        }))

        described_class.head(url: url, options: options)
      end
    end
  end

  describe "exception caching" do
    let(:unreachable_url) { "https://example.local" }

    before do
      described_class.clear_cache!
      allow(Excon).to receive(:get).with(/#{unreachable_url}/, anything).and_raise(error)
      allow(Excon).to receive(:head).with(/#{unreachable_url}/, anything).and_raise(error)
    end

    describe "when Excon times out internally" do
      let(:error) { Excon::Error::Timeout.new("read timeout reached") }

      it "only attempts to reach it once and then plays back the first error without calling the internet" do
        expect(Excon).to receive(:get).with(unreachable_url, anything).once

        expect { described_class.get(url: unreachable_url) }.to raise_error(Excon::Error::Timeout)
        expect { described_class.get(url: unreachable_url) }.to raise_error(Excon::Error::Timeout)
        expect { described_class.get(url: unreachable_url) }.to raise_error(Excon::Error::Timeout)
      end

      it "replays the first error for the host on any request path" do
        expect(Excon).to receive(:get).with(unreachable_url, anything).once

        expect { described_class.get(url: unreachable_url) }.to raise_error(Excon::Error::Timeout)
        expect { described_class.get(url: "#{unreachable_url}/foos") }.to raise_error(Excon::Error::Timeout)
        expect { described_class.get(url: "#{unreachable_url}/foos/bars") }.to raise_error(Excon::Error::Timeout)
      end
    end

    describe "with an HTTP status error" do
      Excon::Error.status_errors.each do |status_code, error_details|
        context "with [#{status_code}] - #{error_details.last}" do
          let(:error_class) { error_details.first }
          let(:error_message) { error_details.last }
          let(:error) { error_class.new(error_message) }

          it "does not cache anything" do
            expect(Excon).to receive(:get).with(/#{unreachable_url}/, anything)

            expect { described_class.get(url: unreachable_url) }.to raise_error(error_class)
            expect { described_class.get(url: "#{unreachable_url}/foos") }.to raise_error(error_class)
            expect { described_class.get(url: "#{unreachable_url}/foos/bars") }.to raise_error(error_class)
          end
        end
      end
    end

    describe "with a non-specific Excon error" do
      let(:error) { Excon::Error.new("Boom!") }

      it "does not cache anything" do
        expect(Excon).to receive(:get).with(/#{unreachable_url}/, anything)

        expect { described_class.get(url: unreachable_url) }.to raise_error(Excon::Error)
        expect { described_class.get(url: "#{unreachable_url}/foos") }.to raise_error(Excon::Error)
        expect { described_class.get(url: "#{unreachable_url}/foos/bars") }.to raise_error(Excon::Error)
      end
    end
  end
end
