# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater"
require "dependabot/ecosystem"
require "dependabot/notices"
require "dependabot/notices_helpers"

RSpec.describe Dependabot::NoticesHelpers do
  let(:dummy_class) do
    Class.new do
      include Dependabot::NoticesHelpers

      attr_accessor :notices

      def initialize
        @notices = []
      end
    end
  end

  let(:dummy_instance) { dummy_class.new }

  let(:package_manager) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize
        detected_version = "1"
        raw_version = "1"
        super(
          name: "bundler", # name
          detected_version: Dependabot::Version.new(detected_version), # detected_version
          version: Dependabot::Version.new(raw_version), # version
          deprecated_versions: [Dependabot::Version.new("1")], # deprecated_versions
          supported_versions: [Dependabot::Version.new("2"), Dependabot::Version.new("3")] # supported_versions
        )
      end
    end.new
  end

  before do
    allow(package_manager).to receive(:unsupported?).and_return(false)
  end

  describe "#add_deprecation_notice" do
    context "when package manager is provided and is deprecated" do
      it "adds a deprecation notice to the notices array" do
        expect do
          dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, version_manager: package_manager)
        end
          .to change { dummy_instance.notices.size }.by(1)

        notice = dummy_instance.notices.first
        expect(notice.mode).to eq("WARN")
        expect(notice.type).to eq("bundler_deprecated_warn")
        expect(notice.package_manager_name).to eq("bundler")
      end

      it "logs deprecation notices line by line" do
        allow(Dependabot.logger).to receive(:warn)

        dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, version_manager: package_manager)

        notice = dummy_instance.notices.first
        notice.description.each_line do |line|
          line = line.strip
          next if line.empty?

          puts "except lines: ##{line}#"
          expect(Dependabot.logger).to have_received(:warn).with(line).once
        end
      end
    end

    context "when package manager is not provided" do
      it "does not add a deprecation notice to the notices array" do
        expect { dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, version_manager: nil) }
          .not_to(change { dummy_instance.notices.size })
      end
    end

    context "when package manager is not deprecated" do
      let(:package_manager) do
        Class.new(Dependabot::Ecosystem::VersionManager) do
          def initialize
            detected_version = "2"
            raw_version = "2"
            super(
              name: "bundler", # name
              detected_version: Dependabot::Version.new(detected_version),
              version: Dependabot::Version.new(raw_version), # version
              deprecated_versions: [Dependabot::Version.new("1")], # deprecated_versions
              supported_versions: [Dependabot::Version.new("2"), Dependabot::Version.new("3")] # supported_versions
            )
          end
        end.new
      end

      it "does not add a deprecation notice to the notices array" do
        expect do
          dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, version_manager: package_manager)
        end
          .not_to(change { dummy_instance.notices.size })
      end
    end

    context "when the language version is deprecated" do
      let(:language_manager) do
        Class.new(Dependabot::Ecosystem::VersionManager) do
          def initialize
            super(
              name: "python", # name
              detected_version: Dependabot::Version.new("3.8"), # version
              version: Dependabot::Version.new("3.8"), # version
              deprecated_versions: [Dependabot::Version.new("3.8")], # deprecated_versions
              supported_versions: [Dependabot::Version.new("3.9"), Dependabot::Version.new("3.10")] # supported_versions
            )
          end
        end.new
      end

      before do
        allow(language_manager).to receive(:unsupported?).and_return(false)
      end

      it "adds a deprecation notice to the notices array" do
        expect do
          dummy_instance
            .add_deprecation_notice(
              notices: dummy_instance.notices,
              version_manager: language_manager,
              version_manager_type: :language
            )
        end.to change { dummy_instance.notices.size }.by(1)

        notice = dummy_instance.notices.first

        expect(notice.mode).to eq("WARN")
        expect(notice.type).to eq("python_deprecated_warn")
        expect(notice.package_manager_name).to eq("python")
      end
    end
  end
end
