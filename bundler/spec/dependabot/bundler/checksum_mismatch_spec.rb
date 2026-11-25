# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve fixtures and matchers in class-scope generated examples.

require "bundler"
require "spec_helper"
require "dependabot/bundler/checksum_mismatch"

RSpec.describe Dependabot::Bundler::ChecksumMismatch do
  subject(:result) { described_class.error_for(helper_error) }

  let(:lockfile_digest) { "e65a37e5" * 8 }
  let(:registry_digest) { "2638e7eb6689a5725c7e16f30cc4aa4e31694dc3ca30d790952526781bd0bb44" }
  let(:lock_name) { "rack (2.2.3)" }
  let(:error_class) { "Bundler::ChecksumMismatchError" }
  let(:helper_error) do
    Dependabot::SharedHelpers::HelperSubprocessFailed.new(
      message: message,
      error_context: {},
      error_class: error_class
    )
  end
  let(:lockfile_checksum) { checksum(lockfile_digest, :lock, "Gemfile.lock:16:16") }
  let(:registry_checksum) { checksum(registry_digest, :api, "https://rubygems.pkg.github.com/acme/") }
  let(:message) { bundler_message(lock_name, lockfile_checksum, registry_checksum) }

  def checksum(digest, type, location)
    Bundler::Checksum.new("sha256", digest, Bundler::Checksum::Source.new(type, location))
  end

  def bundler_message(lock_name, existing, other)
    Bundler::ChecksumMismatchError.new(lock_name, existing, other).message
  end

  context "when the lockfile and the registry disagree" do
    it "names the gem and both checksums, with advice to fix the lockfile" do
      expect(result).to be_a(Dependabot::DependencyChecksumMismatch)
      expect(result.dependency_name).to eq("rack (2.2.3)")
      expect(result.message).to eq(
        "Bundler found mismatched checksums for rack (2.2.3): " \
        "sha256=#{lockfile_digest} from the lockfile CHECKSUMS at Gemfile.lock:16:16, " \
        "but sha256=#{registry_digest} from the API at https://rubygems.pkg.github.com. " \
        "Dependabot can't update this lockfile until they match. Check which copy of the gem is " \
        "correct. If the registry's copy is correct, remove the rack (2.2.3) entry from the " \
        "CHECKSUMS section of your lockfile (and any stale copy of the gem in vendor/cache), " \
        "then run `bundle lock`. Otherwise, republish the gem so the registry serves the expected file."
      )
    end

    it "doesn't repeat Bundler's advice to disable checksum validation" do
      expect(message).to include("disable_checksum_validation")
      expect(result.message).not_to include("disable_checksum_validation")
    end
  end

  context "with the exact message produced by the Bundler 4 native helper" do
    let(:message) do
      <<~MESSAGE
        Bundler found mismatched checksums. This is a potential security risk.
          rack (2.2.3) sha256=#{lockfile_digest}
            from the lockfile CHECKSUMS at ../../../../dependabot-updater/Gemfile.lock:16:16
          rack (2.2.3) sha256=#{registry_digest}
            from the API at https://rubygems.org/

        If you trust the API at https://rubygems.org/, to resolve this issue you can:
          1. remove the matching checksum in ../../../../dependabot-updater/Gemfile.lock:16:16
          2. run `bundle install`

        To ignore checksum security warnings, disable checksum validation with
          `bundle config set --local disable_checksum_validation true`
      MESSAGE
    end

    it "parses it and hides the runner's lockfile path" do
      expect(result.dependency_name).to eq("rack (2.2.3)")
      expect(result.message).to include("from the lockfile CHECKSUMS at Gemfile.lock:16:16, but")
      expect(result.message).to include("from the API at https://rubygems.org.")
      expect(result.message).not_to include("dependabot-updater")
    end
  end

  context "when the registry side is reported first" do
    let(:message) { bundler_message(lock_name, registry_checksum, lockfile_checksum) }

    it "keeps each checksum with its own source" do
      expect(result.message).to start_with(
        "Bundler found mismatched checksums for rack (2.2.3): " \
        "sha256=#{registry_digest} from the API at https://rubygems.pkg.github.com, " \
        "but sha256=#{lockfile_digest} from the lockfile CHECKSUMS at Gemfile.lock:16:16."
      )
    end
  end

  context "with a platform-specific gem" do
    let(:lock_name) { "nokogiri (1.16.0-x86_64-linux)" }

    it "keeps the full lock name" do
      expect(result.dependency_name).to eq("nokogiri (1.16.0-x86_64-linux)")
      expect(result.message).to include("remove the nokogiri (1.16.0-x86_64-linux) entry")
    end
  end

  context "when one checksum comes from several sources" do
    let(:lockfile_checksum) do
      checksum(lockfile_digest, :lock, "Gemfile.lock:16:16").tap do |lock|
        lock.merge!(checksum(lockfile_digest, :gem, "/home/dependabot/app/vendor/cache/rack-2.2.3.gem"))
      end
    end

    it "lists every source and hides the local gem path" do
      expect(result.message).to include(
        "sha256=#{lockfile_digest} from the lockfile CHECKSUMS at Gemfile.lock:16:16 " \
        "and the gem file rack-2.2.3.gem, but"
      )
      expect(result.message).not_to include("/home/dependabot")
    end
  end

  context "when a downloaded gem disagrees with the registry and the lockfile isn't involved" do
    let(:message) do
      bundler_message(
        lock_name,
        checksum(lockfile_digest, :gem, "/tmp/bundle/cache/rack-2.2.3.gem"),
        registry_checksum
      )
    end

    it "doesn't tell the user to edit the lockfile" do
      expect(result.message).to include("from the gem file rack-2.2.3.gem")
      expect(result.message).not_to include("/tmp/bundle")
      expect(result.message).not_to include("CHECKSUMS section")
      expect(result.message).to end_with("Check that the gem served by your registry is the one you expect.")
    end
  end

  context "with a source type Dependabot doesn't know" do
    let(:message) do
      bundler_message(lock_name, lockfile_checksum, checksum(registry_digest, :plugin, "/secret/path"))
    end

    it "describes it generically without its location" do
      expect(result.message).to include("sha256=#{registry_digest} from another source.")
      expect(result.message).not_to include("/secret/path")
    end
  end

  context "when the registry URL includes credentials" do
    {
      "a user and password" => "https://user:s3cr3t@gems.example.com/",
      "a token as the user" => "https://s3cr3t@gems.example.com/",
      "a token in the path" => "https://gem.fury.io/s3cr3t/",
      "a percent-escaped password" => "https://user:s3%40cr3t@gems.example.com/private/"
    }.each do |description, url|
      context "with #{description}" do
        let(:registry_checksum) { checksum(registry_digest, :api, url) }

        it "shows only the registry host" do
          host = URI.parse(url).host
          expect(result.message).to include("from the API at https://#{host}.")
          expect(result.message).not_to include("s3")
        end
      end
    end
  end

  context "when the registry uses a non-default port" do
    let(:registry_checksum) { checksum(registry_digest, :api, "http://localhost:9292/private/") }

    it "keeps the port" do
      expect(result.message).to include("from the API at http://localhost:9292.")
    end
  end

  context "when the registry URL can't be parsed" do
    let(:registry_checksum) { checksum(registry_digest, :api, "not a url") }

    it "describes it generically" do
      expect(result.message).to include("sha256=#{registry_digest} from a registry.")
    end
  end

  context "when the registry URL has no host" do
    let(:registry_checksum) { checksum(registry_digest, :api, "gems/private/") }

    it "describes it generically" do
      expect(result.message).to include("sha256=#{registry_digest} from a registry.")
    end
  end

  context "when the mismatch is on Bundler itself" do
    let(:lock_name) { "bundler (4.0.14)" }

    it "leaves the error unmapped, since it comes from the runner's Bundler" do
      expect(result).to be_nil
    end
  end

  context "when the message can't be parsed" do
    let(:message) { "Bundler found mismatched checksums. This is a potential security risk.\n  garbled" }

    it "returns a generic error without Bundler's text" do
      expect(result).to be_a(Dependabot::DependencyChecksumMismatch)
      expect(result.dependency_name).to be_nil
      expect(result.message).to eq(described_class::GENERIC_MESSAGE)
    end
  end

  context "when the message has no Bundler header" do
    let(:message) { "Something else went wrong" }

    it "returns the generic error" do
      expect(result.message).to eq(described_class::GENERIC_MESSAGE)
    end
  end

  context "when a source line comes before any checksum" do
    let(:message) do
      "Bundler found mismatched checksums. This is a potential security risk.\n" \
        "    from the API at https://rubygems.org/\n"
    end

    it "returns the generic error" do
      expect(result.message).to eq(described_class::GENERIC_MESSAGE)
    end
  end

  context "when a checksum has no source" do
    let(:message) do
      <<~MESSAGE
        Bundler found mismatched checksums. This is a potential security risk.
          rack (2.2.3) sha256=#{lockfile_digest}
          rack (2.2.3) sha256=#{registry_digest}
            from the API at https://rubygems.org/
      MESSAGE
    end

    it "returns the generic error" do
      expect(result.message).to eq(described_class::GENERIC_MESSAGE)
    end
  end

  context "when the two entries name different gems" do
    let(:message) do
      <<~MESSAGE
        Bundler found mismatched checksums. This is a potential security risk.
          rack (2.2.3) sha256=#{lockfile_digest}
            from the lockfile CHECKSUMS at Gemfile.lock:16:16
          rake (13.0.0) sha256=#{registry_digest}
            from the API at https://rubygems.org/
      MESSAGE
    end

    it "returns the generic error" do
      expect(result.message).to eq(described_class::GENERIC_MESSAGE)
    end
  end

  context "when the helper failed with a different error" do
    let(:error_class) { "Bundler::SolveFailure" }

    it { is_expected.to be_nil }
  end
end
