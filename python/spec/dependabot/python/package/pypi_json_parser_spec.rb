# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python"
require "dependabot/python/package/pypi_json_parser"

RSpec.describe Dependabot::Python::Package::PypiJsonParser do
  subject(:parsed) { described_class.new(source_url: source_url).parse(content) }

  let(:source_url) { "https://test-user:test-password@registry.example.test/pypi/demo/json?token=secret#fragment" }
  let(:content) { JSON.generate(data) }
  let(:data) do
    {
      "releases" => {
        "1.2.3" => [
          { "version" => "ignored", "url" => "first.whl", "requires_python" => ">=3.8" },
          { "url" => "second.tar.gz", "requires_python" => ">=3.9" }
        ],
        "1.0beta5prerelease" => [{ "yanked" => [] }]
      }
    }
  end

  it "preserves every eligible distribution and uses the map-key version" do
    expect(parsed.keys).to eq(["1.2.3"])
    expect(parsed.fetch("1.2.3")).to all(be_a(Dependabot::Python::Package::Distribution))
    expect(parsed.fetch("1.2.3").map(&:version_string)).to eq(["1.2.3", "1.2.3"])
    expect(parsed.fetch("1.2.3").map(&:url)).to eq(["first.whl", "second.tar.gz"])
    expect(parsed.fetch("1.2.3").map(&:requires_python)).to eq([">=3.8", ">=3.9"])
  end

  [{}, { "releases" => nil }, { "releases" => {} }, { "releases" => { "1.0.0" => [] } }].each do |value|
    context "with no distributions #{value}" do
      let(:data) { value }

      it "returns no distributions" do
        expect(parsed.values.flatten).to eq([])
      end
    end
  end

  [nil, false, [], { "releases" => [] }, { "releases" => { "1.2.3" => nil } }].each do |value|
    context "with a malformed collection #{value.inspect}" do
      let(:data) { value }

      it "raises an error instead of treating the response as empty" do
        expect { parsed }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end

  context "with a malformed earlier eligible distribution" do
    let(:data) { { "releases" => { "1.2.3" => [{ "downloads" => false }, { "downloads" => 0 }] } } }

    it "rejects the file even when the last file is valid" do
      expect { parsed }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
        expect(error.message).to include("releases[0][0]", "downloads", "https://registry.example.test/pypi/demo/json")
        expect(error.message).not_to include("test-user", "test-password", "token=secret", "#fragment")
        expect(error.cause).to be_nil
      end
    end
  end

  context "with an invalid container under an untrusted version key" do
    let(:data) { { "releases" => { "do-not-echo-this" => nil } } }

    it "uses an index rather than including the untrusted key in the error" do
      expect { parsed }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
        expect(error.message).to include("releases[0]")
        expect(error.message).not_to include("do-not-echo-this")
      end
    end
  end

  context "with malformed JSON" do
    let(:content) { '{"do-not-echo-this":' }

    it "clears the raw parser cause and identifies the format" do
      expect { parsed }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
        expect(error.message).to include("PyPI JSON", "valid JSON")
        expect(error.message).not_to include("do-not-echo-this", "test-password", "token=secret")
        expect(error.cause).to be_nil
      end
    end
  end
end
