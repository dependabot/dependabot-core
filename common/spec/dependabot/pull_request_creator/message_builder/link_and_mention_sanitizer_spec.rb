# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/"\
        "link_and_mention_sanitizer"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::LinkAndMentionSanitizer do
  subject(:sanitizer) do
    described_class.new(github_redirection_service: github_redirection_service)
  end
  let(:github_redirection_service) { "github-redirect.com" }

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

      context "that includes a slash" do
        let(:text) { "Great work on @greysteil/repo!" }
        it { is_expected.to eq(text) }
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

      context "that appears in single tick code quotes" do
        let(:text) { "Great work `@greysteil`!" }
        it { is_expected.to eq(text) }
      end

      context "that appears in double tick code quotes" do
        let(:text) { "Great work ``@greysteil``!" }
        it { is_expected.to eq(text) }
      end

      context "with unmatched single code ticks previously" do
        let(:text) { fixture("changelogs", "sentry.md") }
        it { is_expected.to include("@&#8203;halkeye") }
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

        context "with a mention before and after" do
          let(:text) do
            "```@command```\nThanks to @feelepxyz```@other``` @escape"
          end

          it "sanitizes the mention" do
            expect(sanitize_links_and_mentions).to eq(
              "```@command```\nThanks to [@&#8203;feelepxyz]"\
              "(https://github.com/feelepxyz)"\
              "```@other``` [@&#8203;escape](https://github.com/escape)"
            )
          end
        end

        context "with two code blocks and mention after" do
          let(:text) { "```@command ```\n``` @test``` @feelepxyz" }

          it "sanitizes the mention" do
            expect(sanitize_links_and_mentions).to eq(
              "```@command ```\n``` @test``` "\
              "[@&#8203;feelepxyz](https://github.com/feelepxyz)"
            )
          end
        end

        context "with mentions inside a complex code fence" do
          let(:text) do
            "Take a look at this code: ```` @not-a-mention "\
            "```@not-a-mention``` ````"
          end

          pending "sanitizes the text without touching the code fence" do
            expect(sanitize_links_and_mentions).to eq(
              "Take a look at this code: ```` @not-a-mention "\
              "```@not-a-mention``` ````"
            )
          end

          context "and a real mention after" do
            let(:text) do
              "Take a look at this code: ```` @not-a-mention "\
              "```@not-a-mention``` ```` This is a @mention!"
            end

            pending "sanitizes the text without touching the code fence" do
              expect(sanitize_links_and_mentions).to eq(
                "Take a look at this code: ```` @not-a-mention "\
                "```@not-a-mention``` ```` "\
                "This is a [@&#8203;mention](https://github.com/mention)!"
              )
            end
          end
        end

        context "with mixed syntax code blocks" do
          let(:text) { "```@command ```\n~~~ @test~~~ @feelepxyz" }

          it "sanitizes the mention" do
            expect(sanitize_links_and_mentions).to eq(
              "```@command ```\n~~~ @test~~~ [@&#8203;feelepxyz](https://github.com/feelepxyz)"
            )
          end
        end

        context "with a dangling code block" do
          let(:text) { "@command ``` @feelepxyz" }

          it "sanitizes the mention" do
            expect(sanitize_links_and_mentions).to eq(
              "[@&#8203;command](https://github.com/command) ``` "\
              "[@&#8203;feelepxyz](https://github.com/feelepxyz)"
            )
          end
        end
      end

      context "that is formatted surprisingly" do
        let(:text) { "```````\nThis is a @mention!" }

        it "sanitizes the mention" do
          expect(sanitize_links_and_mentions).to eq(
            "```````\nThis is a [@&#8203;mention](https://github.com/mention)!"
          )
        end
      end
    end

    context "with empty text" do
      let(:text) { "" }
      it { is_expected.to eq(text) }
    end

    context "with ending newline" do
      let(:text) { "Changelog 2.0\n" }
      it { is_expected.to eq(text) }
    end

    context "with an email" do
      let(:text) { "Contact support@dependabot.com for details" }
      it { is_expected.to eq(text) }
    end

    context "with a GitHub link" do
      let(:text) { "Check out https://github.com/my/repo/issues/5" }

      it do
        is_expected.to eq(
          "Check out [my/repo#5](https://github-redirect.com/my/repo/issues/5)"
        )
      end
    end

    context "with a changelog that doesn't need sanitizing" do
      let(:text) { fixture("changelogs", "jsdom.md") }
      let(:github_redirection_service) { "github.com" }

      it "doesn't freeze when parsing the changelog" do
        is_expected.to eq(text)
      end
    end
  end
end
