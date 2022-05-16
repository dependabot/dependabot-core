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
end
