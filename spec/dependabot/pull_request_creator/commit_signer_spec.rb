# frozen_string_literal: true

require "spec_helper"
require "gpgme"
require "dependabot/pull_request_creator/commit_signer"

RSpec.describe Dependabot::PullRequestCreator::CommitSigner do
  subject(:signer) do
    described_class.new(
      author_details: author_details,
      commit_message: "commit_message",
      tree_sha: "tree_sha",
      parent_sha: "parent_sha",
      signature_key: signature_key
    )
  end

  let!(:signature_key) { fixture("keys", "pgp.key") }
  let!(:public_key) { fixture("keys", "pgp.pub") }
  let(:author_details) do
    {
      email: "support@dependabot.com",
      name: "dependabot",
      date: "2018-02-22T23:29:47Z"
    }
  end

  describe "#signature" do
    subject(:signature) { signer.signature }

    let(:text_to_sign) do
      "tree tree_sha\n"\
      "parent parent_sha\n"\
      "author dependabot <support@dependabot.com> 1519342187 +0000\n"\
      "committer dependabot <support@dependabot.com> 1519342187 +0000\n"\
      "\n"\
      "commit_message"
    end

    it "signs the correct text, correctly" do
      signature = signer.signature

      Dependabot::SharedHelpers.in_a_temporary_directory do |dir|
        GPGME::Engine.home_dir = dir.to_s
        GPGME::Key.import(public_key)

        crypto = GPGME::Crypto.new(armor: true)
        crypto.verify(signature, signed_text: text_to_sign) do |sig|
          expect(sig).to be_valid
        end
      end
    end
  end
end
