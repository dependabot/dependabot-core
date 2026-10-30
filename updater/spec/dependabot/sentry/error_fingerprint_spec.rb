# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/sentry/error_fingerprint"

RSpec.describe Dependabot::Sentry::ErrorFingerprint do
  describe ".for" do
    subject(:fingerprint) do
      described_class.for(error: error, package_manager: package_manager)
    end

    let(:package_manager) { "pip" }

    context "with an EOF-backed Excon socket error" do
      let(:error) do
        Excon::Error::Socket.new(EOFError.new).tap do |socket_error|
          socket_error.set_backtrace(
            [
              "/vendor/ruby/gems/excon/lib/excon/socket.rb:90:in 'readline'",
              "/home/dependabot/common/lib/dependabot/registry_client.rb:32:in 'get'",
              "/home/dependabot/python/lib/dependabot/python/package/package_details_fetcher.rb:445:" \
              "in 'registry_response_for_dependency'"
            ]
          )
        end
      end

      it "groups by package manager and the first non-client Dependabot call site" do
        expect(fingerprint).to eq(
          [
            "excon-eof",
            "pip",
            "python/lib/dependabot/python/package/package_details_fetcher.rb:registry_response_for_dependency"
          ]
        )
      end
    end

    context "with another socket error" do
      let(:error) { Excon::Error::Socket.new(Errno::ECONNRESET.new) }

      it { is_expected.to be_nil }
    end

    context "with an error carrying a Dependabot call site" do
      let(:error) do
        Dependabot::DependabotError.new("Security update failed for lodash 1.2.3").tap do |raised|
          raised.set_backtrace(
            [
              "/home/dependabot/dependabot-updater/lib/dependabot/updater/operations/" \
              "create_group_update_pull_request.rb:148:in 'report_failed_dependency_updates_for_security_updates'",
              "/home/dependabot/dependabot-updater/lib/dependabot/updater.rb:70:in 'run'"
            ]
          )
        end
      end

      it "groups by error class, package manager and call site, ignoring the message" do
        expect(fingerprint).to eq(
          [
            "Dependabot::DependabotError",
            "pip",
            "dependabot-updater/lib/dependabot/updater/operations/create_group_update_pull_request.rb:" \
            "report_failed_dependency_updates_for_security_updates"
          ]
        )
      end
    end

    context "with an unrelated error" do
      let(:error) { StandardError.new }

      it { is_expected.to be_nil }
    end
  end
end
