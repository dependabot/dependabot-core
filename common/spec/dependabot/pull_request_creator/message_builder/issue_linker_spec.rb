# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/issue_linker"

RSpec.describe Dependabot::PullRequestCreator::MessageBuilder::IssueLinker do
  subject(:issue_linker) do
    described_class.new(source_url: "https://github.com/a/b")
  end

  describe "#link_issues" do
    subject(:link_issues) { issue_linker.link_issues(text: text) }

    context "with an absolute link" do
      let(:text) { "This is just [#12](https://example.com) text" }
      it { is_expected.to eq(text) }
    end

    context "with a [12] non-link" do
      let(:text) { "This is not a [19] link" }

      it { is_expected.to eq(text) }
    end

    context "with just a number" do
      let(:text) { "This is not a 19 link" }

      it { is_expected.to eq(text) }
    end

    context "with a [12]() link" do
      let(:text) { "This is a [19]() link" }

      it "links the issue" do
        expect(link_issues).
          to eq("This is a [19](https://github.com/a/b/issues/19) link")
      end
    end

    context "with a [#12] link" do
      let(:text) { "This is a [#19] link" }

      it "links the issue" do
        expect(link_issues).
          to eq("This is a [#19](https://github.com/a/b/issues/19) link")
      end
    end

    context "with a #12 link" do
      let(:text) { "This is a #19 link" }

      it "links the issue" do
        expect(link_issues).
          to eq("This is a [#19](https://github.com/a/b/issues/19) link")
      end
    end

    context "with a GH-12 link" do
      let(:text) { "This is a GH-19 link" }

      it "links the issue" do
        expect(link_issues).
          to eq("This is a [GH-19](https://github.com/a/b/issues/19) link")
      end
    end
  end
end
