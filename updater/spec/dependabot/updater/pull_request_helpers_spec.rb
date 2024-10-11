# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater"
require "dependabot/package_manager"
require "dependabot/notices"
require "dependabot/service"

RSpec.describe Dependabot::Updater::PullRequestHelpers do
  let(:dummy_class) do
    Class.new do
      include Dependabot::Updater::PullRequestHelpers

      attr_accessor :notices, :service

      def initialize(service = nil)
        @notices = []
        @service = service
      end
    end
  end

  let(:dummy_instance) { dummy_class.new(service) }

  let(:service) { instance_double(Dependabot::Service) }

  let(:package_manager) do
    Class.new(Dependabot::PackageManagerBase) do
      def name
        "bundler"
      end

      def version
        Dependabot::Version.new("1")
      end

      def deprecated_versions
        [Dependabot::Version.new("1")]
      end

      def supported_versions
        [Dependabot::Version.new("2"), Dependabot::Version.new("3")]
      end
    end.new
  end

  before do
    allow(service).to receive(:record_update_job_warning)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#record_warning_notices" do
    context "when deprecation notice is generated" do
      let(:deprecation_notice) do
        Dependabot::Notice.new(
          mode: "WARN",
          type: "bundler_deprecated_warn",
          package_manager_name: "bundler",
          title: "Package manager deprecation notice",
          description: "Dependabot will stop supporting `bundler v1`!\n" \
                       "\n\nPlease upgrade to one of the following versions: `v2`, or `v3`.\n",
          show_in_pr: true,
          show_alert: true
        )
      end

      it "records it as a warning" do
        expect(service).to receive(:record_update_job_warning).with(
          warn_type: deprecation_notice.type,
          warn_title: deprecation_notice.title,
          warn_description: deprecation_notice.description
        )

        dummy_instance.record_warning_notices([deprecation_notice])
      end
    end

    context "when no deprecation notice is generated" do
      it "does not log or record any warnings" do
        expect(service).not_to receive(:record_update_job_warning)

        dummy_instance.record_warning_notices([])
      end
    end
  end
end
