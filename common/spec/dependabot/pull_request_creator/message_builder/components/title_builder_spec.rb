# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/components/title_builder"
require "dependabot/pull_request_creator/pr_name_prefixer"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::Components::TitleBuilder do
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
end
