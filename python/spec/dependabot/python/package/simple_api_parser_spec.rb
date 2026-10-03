# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python"
require "dependabot/python/package/simple_api_parser"

RSpec.describe Dependabot::Python::Package::SimpleApiParser do
  subject(:parsed_releases) { parser.parse(JSON.dump(response)) }

  let(:parser) do
    described_class.new(
      dependency: dependency,
      project_url: "https://user:pass@registry.example.com/simple/requests/"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.31.0",
      requirements: [],
      package_manager: "pip"
    )
  end
  let(:response) do
    {
      "meta" => { "api-version" => api_version },
      "files" => [
        {
          "filename" => "requests-2.32.3-py3-none-any.whl",
          "url" => "../files/requests-2.32.3-py3-none-any.whl",
          "requires-python" => ">=3.8",
          "yanked" => "Broken release",
          "upload-time" => "2026-08-24T12:34:56Z"
        },
        {
          "filename" => "another-package-1.0.0.tar.gz",
          "url" => "../files/another-package-1.0.0.tar.gz"
        }
      ]
    }
  end
  let(:api_version) { "1.1" }

  it "normalizes matching files into releases" do
    expect(parsed_releases.keys).to eq(["2.32.3"])
    expect(parsed_releases.fetch("2.32.3").first).to have_attributes(
      version_string: "2.32.3",
      requires_python: ">=3.8",
      yanked: true,
      yanked_reason: "Broken release",
      released_at: Time.utc(2026, 8, 24, 12, 34, 56),
      url: "https://registry.example.com/simple/files/requests-2.32.3-py3-none-any.whl"
    )
  end

  context "with multiple distributions for the same version" do
    let(:response) do
      {
        "meta" => { "api-version" => api_version },
        "files" => [
          {
            "filename" => "requests-2.32.3.tar.gz",
            "url" => "../files/requests-2.32.3.tar.gz",
            "yanked" => false
          },
          {
            "filename" => "requests-2.32.3-py3-none-any.whl",
            "url" => "../files/requests-2.32.3-py3-none-any.whl",
            "yanked" => "Broken wheel"
          }
        ]
      }
    end

    it "preserves each distribution's metadata" do
      expect(parsed_releases.fetch("2.32.3")).to contain_exactly(
        have_attributes(
          yanked: false,
          yanked_reason: nil,
          url: "https://registry.example.com/simple/files/requests-2.32.3.tar.gz"
        ),
        have_attributes(
          yanked: true,
          yanked_reason: "Broken wheel",
          url: "https://registry.example.com/simple/files/requests-2.32.3-py3-none-any.whl"
        )
      )
    end
  end

  context "with an unsupported API major version" do
    let(:api_version) { "2.0" }

    it "rejects the response" do
      expect { parsed_releases }
        .to raise_error(Dependabot::DependencyFileNotResolvable, "Unsupported PEP 691 API version: 2.0")
    end
  end

  context "with an omitted API version" do
    let(:response) { { "files" => [] } }

    it "retains the version 1.0 default" do
      expect(parsed_releases).to eq({})
    end
  end

  context "with a newer minor version" do
    let(:api_version) { "1.99" }

    it "continues to read known fields" do
      expect(parsed_releases.keys).to eq(["2.32.3"])
    end
  end

  [false, 1, "", "invalid", "1", "1.1.extra", []].each do |value|
    context "with invalid API version #{value.inspect}" do
      let(:api_version) { value }

      it "rejects the malformed supplied version" do
        expect { parsed_releases }.to raise_error(Dependabot::DependencyFileNotResolvable, /api-version/)
      end
    end
  end

  context "with malformed earlier eligible metadata" do
    let(:response) do
      { "files" => [
        { "filename" => "requests-2.32.3-py3-none-any.whl", "requires-python" => false },
        { "filename" => "requests-2.32.3.tar.gz" }
      ] }
    end

    it "does not discard the malformed first file" do
      expect { parsed_releases }.to raise_error(Dependabot::DependencyFileNotResolvable, /files\[0\].requires-python/)
    end
  end

  context "with malformed unused metadata on an ineligible file" do
    let(:response) do
      { "files" => [
        { "filename" => "unrelated-1.0.0.tar.gz", "requires-python" => false },
        { "filename" => "requests-invalid.tar.gz", "url" => [] },
        { "filename" => nil, "yanked" => {} }
      ] }
    end

    it "keeps eligibility filtering before metadata decoding" do
      expect(parsed_releases).to eq({})
    end
  end

  [nil, [], { "meta" => false }, { "files" => nil }, { "files" => [nil] }].each do |value|
    context "with a malformed response shape #{value.inspect}" do
      let(:response) { value }

      it "raises a contextual response error" do
        expect { parsed_releases }.to raise_error(Dependabot::DependencyFileNotResolvable, /Simple API JSON/)
      end
    end
  end
end
