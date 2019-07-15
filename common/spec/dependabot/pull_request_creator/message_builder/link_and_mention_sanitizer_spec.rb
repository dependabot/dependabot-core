# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/"\
        "link_and_mention_sanitizer"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::LinkAndMentionSanitizer do
  subject(:sanitizer) do
    described_class.new(github_redirection_service: "github-redirect.com")
  end

  describe "#sanitize_links_and_mentions" do
    subject(:sanitize_links_and_mentions) do
      sanitizer.sanitize_links_and_mentions(text: text)
    end

    context "with an @-mention" do
      let(:text) { "Great work @greysteil!" }

      it "sanitizes the text" do
        expect(sanitize_links_and_mentions).
          to eq("Great work [@&#8203;greysteil](https://github.com/greysteil)!")
      end

      context "that includes a dash" do
        let(:text) { "Great work @greysteil-work!" }

        it "sanitizes the text" do
          expect(sanitize_links_and_mentions).to eq(
            "Great work [@&#8203;greysteil-work]"\
            "(https://github.com/greysteil-work)!"
          )
        end
      end

      context "that is in brackets" do
        let(:text) { "The team (by @greysteil) etc." }

        it "sanitizes the text" do
          expect(sanitize_links_and_mentions).to eq(
            "The team (by [@&#8203;greysteil](https://github.com/greysteil)) "\
            "etc."
          )
        end
      end

      context "that appears in code quotes" do
        let(:text) { "Great work `@greysteil`!" }
        it { is_expected.to eq(text) }
      end

      context "that appears in codeblock quotes" do
        let(:text) { "``` @model ||= 123```" }
        it { is_expected.to eq(text) }

        context "that use `~`" do
          let(:text) { "~~~ @model ||= 123~~~" }
          it { is_expected.to eq(text) }
        end

        context "with a mention before" do
          let(:text) do
            "@greysteil wrote this:\n\n``` @model ||= 123\n```\n\n"\
            "Review by @hmarr!"
          end

          it "sanitizes the text" do
            expect(sanitize_links_and_mentions).to eq(
              "[@&#8203;greysteil](https://github.com/greysteil) wrote this:"\
              "\n\n``` @model ||= 123\n```\n\n"\
              "Review by [@&#8203;hmarr](https://github.com/hmarr)!"
            )
          end
        end
      end

      context "that is formatted suprisingly" do
        let(:text) { "```````\nThis is an @mention!" }

        it "sanitizes the text" do
          expect(sanitize_links_and_mentions).to eq(
            "```````\nThis is an [@&#8203;mention](https://github.com/mention)!"
          )
        end
      end
    end

    context "with an email" do
      let(:text) { "Contact support@dependabot.com for details" }
      it { is_expected.to eq(text) }
    end
  end
end
