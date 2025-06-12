# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/update_checker/latest_version_finder"
require "dependabot/pub/package/package_details_fetcher"
require "dependabot/pub/version"

require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Pub::UpdateChecker::LatestVersionFinder do
  subject(:latest_version_finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "pub"
    )
  end

  let(:dependency_files) do
    files = project_dependency_files(project)
    files.each do |file|
      if defined?(git_dir)
        file.content.gsub!("$GIT_DIR", git_dir)
        file.content.gsub!("$REF", dependency_version)
      end
    end
    files
  end

  let(:requirements) { [] }
  let(:dependency_name) { "lints" }
  let(:requirements_update_strategy) { nil }
  let(:dependency_version) { "0.1.0" }
  let(:project) { "can_update" }

  let(:credentials) { [] }

  describe "#current_report" do
    context "when the response is successful" do
      it "can fetch current report" do
        report = latest_version_finder.current_report

        expect(report).not_to be_nil

        expect(report["name"]).to eq(dependency_name)
        expect(report["version"]).to be_a(String)
        expect(report["latest"]).to be_a(String)
      end
    end

    context "with latest version" do
      it "fetches latest versions" do
        versions = latest_version_finder

        # version resolution is not deterministic and response may return empty value
        expect(versions.latest_version).to be_a(String).or be_nil
        expect(versions.latest_resolvable_version).to be_a(String).or be_nil
        expect(versions.latest_resolvable_version_with_no_unlock).to be_a(String).or be_nil
        expect(versions.latest_version_resolvable_with_full_unlock).to be_a(String).or be_nil
      end
    end
  end
end
