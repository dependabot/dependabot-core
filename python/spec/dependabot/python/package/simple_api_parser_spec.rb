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
    expect(parsed_releases).to eq(
      "2.32.3" => [{
        "version" => "2.32.3",
        "requires_python" => ">=3.8",
        "yanked" => true,
        "yanked_reason" => "Broken release",
        "upload_time" => "2026-08-24T12:34:56Z",
        "url" => "https://registry.example.com/simple/files/requests-2.32.3-py3-none-any.whl"
      }]
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
        hash_including(
          "yanked" => false,
          "yanked_reason" => nil,
          "url" => "https://registry.example.com/simple/files/requests-2.32.3.tar.gz"
        ),
        hash_including(
          "yanked" => true,
          "yanked_reason" => "Broken wheel",
          "url" => "https://registry.example.com/simple/files/requests-2.32.3-py3-none-any.whl"
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
end
