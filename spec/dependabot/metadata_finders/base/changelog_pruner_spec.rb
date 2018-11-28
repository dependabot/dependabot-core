# frozen_string_literal: true

require "json"
require "base64"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/base/changelog_pruner"

RSpec.describe Dependabot::MetadataFinders::Base::ChangelogPruner do
  subject(:pruner) do
    described_class.new(
      changelog_text: changelog_text,
      dependency: dependency
    )
  end
  let(:changelog_text) do
    Base64.decode64(JSON.parse(changelog_body).fetch("content")).
      force_encoding("UTF-8").encode
  end
  let(:changelog_body) { fixture("github", "changelog_contents.json") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      previous_version: dependency_previous_version,
      package_manager: package_manager
    )
  end
  let(:package_manager) { "bundler" }
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_version) { "1.0.0" }

  describe "#includes_new_version?" do
    subject(:includes_new_version) { pruner.includes_new_version? }

    context "when the new version is included" do
      it { is_expected.to eq(true) }
    end

    context "when the new version is not included" do
      let(:dependency_version) { "5.0.0" }
      it { is_expected.to eq(false) }
    end
  end

  describe "#pruned_text" do
    subject(:pruned_text) { pruner.pruned_text }
    let(:dependency_version) { "1.4.0" }
    let(:dependency_previous_version) { "1.0.0" }

    let(:expected_pruned_changelog) do
      "## 1.4.0 - December 24, 2014\n\n"\
      "- Add support for custom calendar load paths\n"\
      "- Remove the 'sepa' calendar\n\n\n"\
      "## 1.3.0 - December 2, 2014\n\n"\
      "- Add `Calendar#previous_business_day`\n\n\n"\
      "## 1.2.0 - November 15, 2014\n\n"\
      "- Add TARGET calendar\n\n\n"\
      "## 1.1.0 - September 30, 2014\n\n"\
      "- Add 2015 holiday definitions"
    end

    it { is_expected.to eq(expected_pruned_changelog) }

    context "that has non-standard characters" do
      let(:changelog_body) do
        fixture("github", "changelog_contents_japanese.json")
      end
      let(:dependency_version) { "0.0.6" }

      it { is_expected.to start_with("!! 0.0.5から0.0.6の変更点:") }
    end

    context "where the olf version is a substring of the new one" do
      let(:changelog_text) { fixture("changelogs", "rails52.md") }
      let(:dependency_version) { "5.2.1.1" }
      let(:dependency_previous_version) { "5.2.1" }

      it "prunes the changelog correctly" do
        expect(pruned_text).
          to eq("## Rails 5.2.1.1 (November 27, 2018) ##\n\n*   No changes.")
      end
    end

    context "that is in reverse order" do
      let(:changelog_body) do
        fixture("github", "changelog_contents_reversed.json")
      end
      let(:dependency_version) { "1.11.1" }
      let(:dependency_previous_version) { "1.10.0" }

      # Ideally we'd prune the 1.10.0 entry off, but it's tricky.
      let(:expected_pruned_changelog) do
        "## 1.10.0 - September 20, 2017\n\n"\
        "- Add 2018-2019 Betalingsservice holiday definitions\n\n"\
        "## 1.11.1 - December 20, 2017\n\n"\
        "- Add 2017-2018 BECS holiday definitions"
      end

      it { is_expected.to eq(expected_pruned_changelog) }
    end

    context "when the dependency has no previous version" do
      let(:dependency_previous_version) { nil }

      it "gets the right content" do
        expect(pruned_text).to start_with("## 1.4.0 - December 24, 2014")
        expect(pruned_text).to end_with("- Initial public release")
      end
    end

    context "with headers that contain comparison links" do
      let(:changelog_body) do
        fixture("github", "changelog_contents_comparison_links.json")
      end
      let(:dependency_version) { "3.3.0" }
      let(:dependency_previous_version) { "3.2.1" }

      it "gets the right content" do
        expect(pruned_text).to start_with("# [3.3.0](https://github.")
        expect(pruned_text).to end_with("<a name=\"3.2.1\"></a>")
      end
    end

    context "with headers that are bullets" do
      let(:changelog_body) do
        fixture("github", "changelog_contents_bullets.json")
      end
      let(:dependency_version) { "2.9.1" }
      let(:dependency_previous_version) { "2.9.0" }

      it "gets the right content" do
        expect(pruned_text).
          to eq(
            "* 2.9.1\n"\
            "    * IPv6 support. Thanks https://github.com/amashinchi"
          )
      end
    end

    context "with no relevant versions" do
      let(:dependency_version) { "1.13.0" }
      let(:dependency_previous_version) { "1.12.0" }

      it { is_expected.to be_nil }
    end

    context "with relevant releases but not exact match" do
      let(:dependency_version) { "1.13.0" }
      let(:dependency_previous_version) { "1.4.5" }

      it "gets the right content" do
        expect(pruned_text).to start_with("## 1.11.1")
        expect(pruned_text).to end_with("- Initial public release")
      end
    end

    context "when the changelog doesn't include the previous version" do
      let(:dependency_previous_version) { "0.0.1" }

      it "gets the right content" do
        expect(pruned_text).to start_with("## 1.4.0 - December 24, 2014")
        expect(pruned_text).to end_with("- Initial public release")
      end
    end

    context "when the changelog doesn't include the new version" do
      let(:dependency_version) { "2.0.0" }

      it "gets the right content" do
        expect(pruned_text).to start_with("## 1.11.1 - December 20")
        expect(pruned_text).to end_with("- Add 2015 holiday definitions")
      end

      context "and the previous version is the latest in the changelog" do
        let(:dependency_previous_version) { "1.11.1" }
        it { is_expected.to be_nil }
      end
    end
  end
end
