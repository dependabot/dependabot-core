# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater"
require "dependabot/ecosystem"
require "dependabot/notices"
require "dependabot/notices_helpers"

# A stub package manager for testing purposes.
class StubVersionManager < Dependabot::Ecosystem::VersionManager
  def initialize(name:, detected_version:, raw_version:, deprecated_versions: [], supported_versions: [],
                 support_later_versions: false)
    @support_later_versions = support_later_versions
    super(
      name: name,
      detected_version: Dependabot::Version.new(detected_version),
      version: raw_version.nil? ? nil : Dependabot::Version.new(raw_version),
      deprecated_versions: deprecated_versions,
      supported_versions: supported_versions
    )
  end

  attr_reader :support_later_versions

  sig { override.returns(T::Boolean) }
  def unsupported?
    return false unless version

    version < supported_versions.first
  end

  sig { override.returns(T::Boolean) }
  def support_later_versions?
    support_later_versions
  end
end

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
  let(:detected_version) { Dependabot::Version.new("1") }
  let(:raw_version) { Dependabot::Version.new("1.0.1") }
  let(:deprecated_versions) { [Dependabot::Version.new("1")] }
  let(:supported_versions) { [Dependabot::Version.new("2"), Dependabot::Version.new("3")] }
  let(:version_manager_type) { :package_manager }

  let(:version_manager) do
    StubVersionManager.new(
      name: "bundler",
      detected_version: detected_version,
      raw_version: raw_version,
      deprecated_versions: deprecated_versions,
      supported_versions: supported_versions
    )
  end

  before do
    allow(version_manager).to receive(:unsupported?).and_return(false)
  end

  describe "#add_deprecation_notice" do
    context "when version manager is provided" do
      context "when version manager is deprecated" do
        let(:detected_version) { Dependabot::Version.new("1") }
        let(:deprecated_versions) { [Dependabot::Version.new("1")] }

        it "adds a deprecation notice to the notices array" do
          expect do
            dummy_instance.add_deprecation_notice(
              notices: dummy_instance.notices,
              version_manager: version_manager
            )
          end.to change { dummy_instance.notices.size }.by(1)

          notice = dummy_instance.notices.first
          expect(notice.mode).to eq("WARN")
          expect(notice.type).to eq("bundler_deprecated_warn")
          expect(notice.package_manager_name).to eq("bundler")
        end

        it "logs deprecation notices line by line" do
          allow(Dependabot.logger).to receive(:warn)

          dummy_instance.add_deprecation_notice(
            notices: dummy_instance.notices,
            version_manager: version_manager
          )

          notice = dummy_instance.notices.first
          notice.description.each_line do |line|
            line = line.strip
            next if line.empty?

            expect(Dependabot.logger).to have_received(:warn).with(line).once
          end
        end
      end

      context "when version manager is not deprecated" do
        let(:detected_version) { Dependabot::Version.new("2") }
        let(:deprecated_versions) { [Dependabot::Version.new("1")] }

        it "does not add a deprecation notice to the notices array" do
          expect do
            dummy_instance.add_deprecation_notice(
              notices: dummy_instance.notices,
              version_manager: version_manager
            )
          end.not_to(change { dummy_instance.notices.size })
        end
      end

      context "when raw_version is nil" do
        let(:raw_version) { nil }
        let(:detected_version) { Dependabot::Version.new("1") }

        it "adds a deprecation notice using detected_version" do
          expect do
            dummy_instance.add_deprecation_notice(
              notices: dummy_instance.notices,
              version_manager: version_manager
            )
          end.to change { dummy_instance.notices.size }.by(1)

          notice = dummy_instance.notices.first
          expect(notice.description).to include("Dependabot will stop supporting `bundler v1`!")
        end
      end
    end

    context "when version manager is not provided" do
      it "does not add a deprecation notice to the notices array" do
        expect do
          dummy_instance.add_deprecation_notice(
            notices: dummy_instance.notices,
            version_manager: nil
          )
        end.not_to(change { dummy_instance.notices.size })
      end
    end

    context "when language version is deprecated" do
      let(:language_manager) do
        StubVersionManager.new(
          name: "python",
          detected_version: Dependabot::Version.new("3.8"),
          raw_version: Dependabot::Version.new("3.8"),
          deprecated_versions: [Dependabot::Version.new("3.8")],
          supported_versions: [Dependabot::Version.new("3.9"), Dependabot::Version.new("3.10")]
        )
      end

      before do
        allow(language_manager).to receive(:unsupported?).and_return(false)
      end

      it "adds a deprecation notice to the notices array" do
        expect do
          dummy_instance.add_deprecation_notice(
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
