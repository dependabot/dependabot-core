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

    context "with an Excon timeout" do
      let(:package_manager) { "npm_and_yarn" }
      let(:error) do
        Excon::Error::Timeout.new("read timeout reached").tap do |timeout|
          timeout.set_backtrace(
            [
              "/vendor/ruby/gems/excon/lib/excon/socket.rb:373:in 'Excon::Socket#select_with_timeout'",
              "/home/dependabot/common/lib/dependabot/registry_client.rb:32:in 'Dependabot::RegistryClient.get'",
              "/home/dependabot/npm_and_yarn/lib/dependabot/npm_and_yarn/package/package_details_fetcher.rb:224:" \
              "in 'Dependabot::NpmAndYarn::Package::PackageDetailsFetcher#fetch_npm_response'"
            ]
          )
        end
      end

      it "groups by timeout category, package manager, and the first non-client Dependabot call site" do
        expect(fingerprint).to eq(
          [
            "excon-timeout",
            "npm_and_yarn",
            "npm_and_yarn/lib/dependabot/npm_and_yarn/package/package_details_fetcher.rb:" \
            "Dependabot::NpmAndYarn::Package::PackageDetailsFetcher#fetch_npm_response"
          ]
        )
      end

      context "with a different package manager and call site" do
        let(:package_manager) { "gradle" }
        let(:error) do
          Excon::Error::Timeout.new("read timeout reached").tap do |timeout|
            timeout.set_backtrace(
              [
                "/home/dependabot/common/lib/dependabot/registry_client.rb:32:in 'Dependabot::RegistryClient.get'",
                "/home/dependabot/gradle/lib/dependabot/gradle/package/package_details_fetcher.rb:38:" \
                "in 'Dependabot::Gradle::Package::EofRetry.get'"
              ]
            )
          end
        end

        it "keeps the failures separate" do
          expect(fingerprint).to eq(
            [
              "excon-timeout",
              "gradle",
              "gradle/lib/dependabot/gradle/package/package_details_fetcher.rb:Dependabot::Gradle::Package::EofRetry.get"
            ]
          )
        end
      end

      context "without a package manager or backtrace" do
        let(:package_manager) { nil }
        let(:error) { Excon::Error::Timeout.new("read timeout reached") }

        it { is_expected.to eq(%w(excon-timeout unknown-package-manager unknown-call-site)) }
      end
    end

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

    context "with an unrelated error" do
      let(:error) { StandardError.new }

      it { is_expected.to be_nil }
    end
  end
end
