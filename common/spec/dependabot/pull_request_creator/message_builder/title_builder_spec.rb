# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/title_builder"
require "dependabot/pull_request_creator/pr_name_prefixer"

RSpec.describe Dependabot::PullRequestCreator::MessageBuilder::TitleBuilder do
  before do
    Dependabot::Dependency.register_production_check(
      "npm_and_yarn",
      lambda do |groups|
        return true if groups.empty?
        return true if groups.include?("optionalDependencies")

        groups.include?("dependencies")
      end
    )
  end

  describe "#build" do
    context "with no prefix" do
      subject(:builder) do
        described_class.new(base_title: "bump lodash from 4.0.0 to 5.0.0")
      end

      it "returns the base title unchanged" do
        expect(builder.build).to eq("bump lodash from 4.0.0 to 5.0.0")
      end
    end

    context "with explicit commit_message_options prefix" do
      subject(:builder) do
        described_class.new(
          base_title: "bump lodash from 4.0.0 to 5.0.0",
          commit_message_options: { prefix: "[ci]" },
          dependencies: dependencies
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "lodash",
            version: "5.0.0",
            previous_version: "4.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{ file: "package.json", requirement: "^5.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "package.json", requirement: "^4.0.0", groups: [], source: nil }]
          )
        ]
      end

      it "applies the prefix" do
        expect(builder.build).to eq("[ci]: bump lodash from 4.0.0 to 5.0.0")
      end
    end

    context "with prefix ending in space" do
      subject(:builder) do
        described_class.new(
          base_title: "bump lodash from 4.0.0 to 5.0.0",
          commit_message_options: { prefix: "[ci] " },
          dependencies: dependencies
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "lodash",
            version: "5.0.0",
            previous_version: "4.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{ file: "package.json", requirement: "^5.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "package.json", requirement: "^4.0.0", groups: [], source: nil }]
          )
        ]
      end

      it "does not double-space" do
        expect(builder.build).to eq("[ci] bump lodash from 4.0.0 to 5.0.0")
      end
    end

    context "with include_scope option" do
      subject(:builder) do
        described_class.new(
          base_title: "bump lodash from 4.0.0 to 5.0.0",
          commit_message_options: { prefix: "chore", include_scope: true },
          dependencies: dependencies
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "lodash",
            version: "5.0.0",
            previous_version: "4.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^5.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^4.0.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        ]
      end

      it "includes scope in the prefix" do
        expect(builder.build).to eq("chore(deps): bump lodash from 4.0.0 to 5.0.0")
      end
    end

    context "with prefix_development for dev dependency" do
      subject(:builder) do
        described_class.new(
          base_title: "bump eslint from 7.0.0 to 8.0.0",
          commit_message_options: { prefix: "fix", prefix_development: "chore" },
          dependencies: dependencies
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "eslint",
            version: "8.0.0",
            previous_version: "7.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^8.0.0",
              groups: ["devDependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^7.0.0",
              groups: ["devDependencies"],
              source: nil
            }]
          )
        ]
      end

      it "uses the development prefix" do
        expect(builder.build).to eq("chore: bump eslint from 7.0.0 to 8.0.0")
      end
    end

    context "with a PrNamePrefixer" do
      subject(:builder) do
        described_class.new(
          base_title: "bump lodash from 4.0.0 to 5.0.0",
          prefixer: prefixer
        )
      end

      let(:prefixer) { instance_double(Dependabot::PullRequestCreator::PrNamePrefixer) }

      before do
        allow(prefixer).to receive_messages(pr_name_prefix: "⬆️ ", capitalize_first_word?: true)
      end

      it "uses prefixer for prefix and capitalization" do
        expect(builder.build).to eq("⬆️ Bump lodash from 4.0.0 to 5.0.0")
      end
    end

    context "with empty prefix string" do
      subject(:builder) do
        described_class.new(
          base_title: "bump lodash from 4.0.0 to 5.0.0",
          commit_message_options: { prefix: "" },
          dependencies: dependencies
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "lodash",
            version: "5.0.0",
            previous_version: "4.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{ file: "package.json", requirement: "^5.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "package.json", requirement: "^4.0.0", groups: [], source: nil }]
          )
        ]
      end

      it "returns the base title without prefix" do
        expect(builder.build).to eq("bump lodash from 4.0.0 to 5.0.0")
      end
    end
  end

  describe ".multi_ecosystem_base_title" do
    it "returns the multi-ecosystem title with plural updates" do
      expect(described_class.multi_ecosystem_base_title(group_name: "my-dependencies", update_count: 3)).to eq(
        "bump the \"my-dependencies\" group with 3 updates across multiple ecosystems"
      )
    end

    context "with a single update" do
      it "returns singular update" do
        expect(described_class.multi_ecosystem_base_title(group_name: "my-dependencies", update_count: 1)).to eq(
          "bump the \"my-dependencies\" group with 1 update across multiple ecosystems"
        )
      end
    end

    context "with a different group name" do
      it "uses the group name" do
        expect(described_class.multi_ecosystem_base_title(group_name: "security-patches", update_count: 3)).to eq(
          "bump the \"security-patches\" group with 3 updates across multiple ecosystems"
        )
      end
    end
  end
end
