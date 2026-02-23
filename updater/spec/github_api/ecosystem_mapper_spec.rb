# typed: false
# frozen_string_literal: true

require "spec_helper"

require "github_api/ecosystem_mapper"

RSpec.describe GithubApi::EcosystemMapper do
  describe ".ecosystem_for" do
    {
      "bundler" => "rubygems",
      "npm_and_yarn" => "npm",
      "bun" => "npm",
      "pip" => "pypi",
      "uv" => "pypi",
      "go_modules" => "golang",
      "maven" => "maven",
      "gradle" => "gradle",
      "nuget" => "nuget",
    }.each do |package_manager, expected_ecosystem|
      it "maps #{package_manager} to #{expected_ecosystem}" do
        expect(described_class.ecosystem_for(package_manager)).to eq(expected_ecosystem)
      end
    end

    context "when the package manager has no mapping" do
      it "returns 'other'" do
        expect(described_class.ecosystem_for("cobol")).to eq("other")
      end

      it "logs a warning" do
        expect(Dependabot.logger).to receive(:warn).with(
          a_string_including(
            "Unknown Dependency Graph ecosystem for package manager: cobol"
          )
        )

        described_class.ecosystem_for("cobol")
      end
    end
  end
end
