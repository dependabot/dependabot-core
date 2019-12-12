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
          to eq("<p>Great work <a href=\"https://github.com/greysteil\">"\
            "@​greysteil</a>!</p>\n")
      end

      context "that includes a dash" do
        let(:text) { "Great work @greysteil-work!" }

        it "sanitizes the text" do
          expect(sanitize_links_and_mentions).to eq(
            "<p>Great work <a href=\"https://github.com/greysteil-work\">"\
            "@​greysteil-work</a>!</p>\n"
          )
        end
      end

      context "that includes a slash" do
        let(:text) { "Great work on @greysteil/repo!" }
        it { is_expected.to eq("<p>Great work on @greysteil/repo!</p>\n") }
      end

      context "that is in brackets" do
        let(:text) { "The team (by @greysteil) etc." }

        it "sanitizes the text" do
          expect(sanitize_links_and_mentions).to eq(
            "<p>The team (by <a href=\"https://github.com/greysteil\">"\
            "@​greysteil</a>) etc.</p>\n"
          )
        end
      end

      context "that appears in single tick code quotes" do
        let(:text) { "Great work `@greysteil`!" }
        it { is_expected.to eq(text) }
      end

      context "that appears in double tick code quotes" do
        let(:text) { "Great work ``@greysteil``!" }
        it { is_expected.to eq("<p>Great work <code>@greysteil</code>!</p>\n") }
      end

      context "with unmatched single code ticks previously" do
        let(:text) { fixture("changelogs", "sentry.md") }
        it { is_expected.to include("@&#8203;halkeye") }
      end

      context "that appears in codeblock quotes" do
        let(:text) { "``` @model ||= 123```" }
        it do
          is_expected.to eq(
            "<pre><code></code></pre>\n<p>"\
            "<a href=\"https://github.com/model\">@​model</a> ||= 123```</p>\n"
          )
        end

        context "that use `~`" do
          let(:text) { "~~~ @model ||= 123~~~" }
          it do
            is_expected.to eq(
              "<pre><code></code></pre>\n<p>"\
              "<a href=\"https://github.com/model\">"\
              "@​model</a> ||= 123~~~</p>\n"
            )
          end
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
            "<pre><code></code></pre>\n<pre><code></code></pre>\n<p>`\n"\
            "This is a <a href=\"https://github.com/mention\">"\
            "@​mention</a>!</p>\n"
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
      it { is_expected.to eq("<p>Changelog 2.0</p>\n") }
    end

    context "with an email" do
      let(:text) { "Contact support@dependabot.com for details" }
      it do
        is_expected.to eq(
          "<p>Contact <a href=\"mailto:support@dependabot.com\">"\
          "support@dependabot.com</a> for details</p>\n"
        )
      end
    end

    context "with a GitHub link" do
      let(:text) { "Check out https://github.com/my/repo/issues/5" }

      it do
        is_expected.to eq(
          "<p>Check out <a href=\"https://github-redirect.com/my/repo/"\
          "issues/5\">my/repo#5</a></p>\n"
        )
      end
    end

    context "with a markdown footer" do
      let(:text) do
        "[Updated the `libm` dependency to 0.2][144]\n\n"\
        "[144]: https://github.com/rust-num/num-traits/pull/144"
      end

      it do
        is_expected.to eq(
          "<p><a href=\"https://github-redirect.com/rust-num/num-traits/"\
          "pull/144\">Updated the <code>libm</code> dependency to 0.2</a></p>\n"
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
