# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/authed_url_builder"

RSpec.describe Dependabot::Python::AuthedUrlBuilder do
  describe ".authed_url" do
    subject(:authed_url) { described_class.authed_url(credential: credential) }

    context "without a token" do
      let(:credential) do
        {
          "type" => "python_index",
          "index-url" => "https://pypi.weasyldev.com/weasyl/source/+simple",
          "replaces-base" => "true"
        }
      end

      it "leaves the URL alone" do
        expect(authed_url).
          to eq("https://pypi.weasyldev.com/weasyl/source/+simple")
      end
    end

    context "with a token" do
      let(:credential) do
        {
          "type" => "python_index",
          "index-url" => "https://pypi.weasyldev.com/weasyl/source/+simple",
          "token" => token,
          "replaces-base" => "true"
        }
      end

      context "that doesn't include a :" do
        let(:token) { "token" }

        it "builds the URL correctly" do
          expect(authed_url).
            to eq("https://token@pypi.weasyldev.com/weasyl/source/+simple")
        end

        context "that is already base64 encoded" do
          let(:token) { "bXk6cGFzcw==" }

          it "builds the URL correctly" do
            expect(authed_url).
              to eq("https://my:pass@pypi.weasyldev.com/weasyl/source/+simple")
          end
        end
      end

      context "that includes a :" do
        let(:token) { "token:pass" }

        it "builds the URL correctly" do
          expect(authed_url).
            to eq("https://token:pass@pypi.weasyldev.com/weasyl/source/+simple")
        end
      end

      context "that includes an @" do
        let(:token) { "token:pass@23" }

        it "builds the URL correctly" do
          expect(authed_url). to eq(
            "https://token:pass%4023@pypi.weasyldev.com/weasyl/source/+simple"
          )
        end
      end

      context "that includes an #" do
        let(:token) { "token:pass#23" }

        it "builds the URL correctly" do
          expect(authed_url). to eq(
            "https://token:pass%2323@pypi.weasyldev.com/weasyl/source/+simple"
          )
        end
      end

      context "that has multiple colons" do
        let(:token) { "token:pass:23" }

        it "builds the URL correctly" do
          expect(authed_url). to eq(
            "https://token:pass%3A23@pypi.weasyldev.com/weasyl/source/+simple"
          )
        end
      end

      context "that includes an @ and is base64 encoded" do
        let(:token) { "dG9rZW46cGFzc0AyMw==" }

        it "builds the URL correctly" do
          expect(authed_url). to eq(
            "https://token:pass%4023@pypi.weasyldev.com/weasyl/source/+simple"
          )
        end
      end
    end
  end
end
