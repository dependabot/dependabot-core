# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::Wrapper::PropertiesReconciler do
  describe ".reconcile" do
    subject(:reconciled) do
      described_class.reconcile(
        original_content: original_content,
        regenerated_content: regenerated_content
      )
    end

    let(:original_content) do
      <<~PROPS
        # platform-managed wrapper config
        distributionBase=GRADLE_USER_HOME
        distributionPath=wrapper/dists
        distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip
        networkTimeout=10000
        retries=3
        retryBackOffMs=1000
        validateDistributionUrl=true
        zipStoreBase=GRADLE_USER_HOME
        zipStorePath=wrapper/dists
        myCompany.customKey=keep-me
      PROPS
    end

    # Mimics what Gradle's wrapper task writes: sorted keys, no comments, defaults for everything
    # the minimal build did not configure.
    let(:regenerated_content) do
      <<~PROPS
        distributionBase=GRADLE_USER_HOME
        distributionPath=wrapper/dists
        distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip
        networkTimeout=10000
        retries=0
        retryBackOffMs=500
        validateDistributionUrl=false
        zipStoreBase=GRADLE_USER_HOME
        zipStorePath=wrapper/dists
      PROPS
    end

    it "takes the new distributionUrl from the regenerated file" do
      expect(reconciled).to include("distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip")
      expect(reconciled).not_to include("gradle-8.14.2-bin.zip")
    end

    it "preserves the user's customized values (the #15312 bug)" do
      expect(reconciled).to include("retries=3")
      expect(reconciled).to include("retryBackOffMs=1000")
      expect(reconciled).to include("networkTimeout=10000")
      expect(reconciled).to include("validateDistributionUrl=true")
    end

    it "preserves comments, custom keys and structural keys" do
      expect(reconciled).to include("# platform-managed wrapper config")
      expect(reconciled).to include("myCompany.customKey=keep-me")
      expect(reconciled).to include("distributionBase=GRADLE_USER_HOME")
      expect(reconciled).to include("zipStorePath=wrapper/dists")
    end

    context "when the regenerated file adds a checksum the user already had" do
      let(:original_content) do
        <<~PROPS
          distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip
          distributionSha256Sum=oldsum
        PROPS
      end
      let(:regenerated_content) do
        <<~PROPS
          distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip
          distributionSha256Sum=newsum
        PROPS
      end

      it "updates the checksum" do
        expect(reconciled).to include("distributionSha256Sum=newsum")
        expect(reconciled).not_to include("oldsum")
      end
    end

    context "when the user had no checksum" do
      let(:original_content) do
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip\n"
      end
      let(:regenerated_content) do
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip\n"
      end

      it "does not introduce a checksum" do
        expect(reconciled).not_to include("distributionSha256Sum")
      end
    end

    context "when the regenerated file introduces a managed key absent from the original" do
      let(:original_content) do
        <<~PROPS
          # keep me
          distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip
          networkTimeout=10000
        PROPS
      end
      let(:regenerated_content) do
        <<~PROPS
          distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip
          distributionSha256Sum=newsum
        PROPS
      end

      it "appends the new managed key while preserving original content and order" do
        expect(reconciled).to include("distributionSha256Sum=newsum")
        expect(reconciled).to include("# keep me")
        expect(reconciled).to include("networkTimeout=10000")
        # appended at the end, after the preserved original lines
        expect(reconciled.index("distributionSha256Sum"))
          .to be > reconciled.index("networkTimeout")
      end
    end

    context "when there is no original content" do
      let(:original_content) { nil }
      let(:regenerated_content) { "distributionUrl=foo\n" }

      it "returns nil so the regenerated file is kept as-is" do
        expect(reconciled).to be_nil
      end
    end

    context "when there is no regenerated content" do
      let(:original_content) { "distributionUrl=foo\n" }
      let(:regenerated_content) { nil }

      it "returns the original unchanged" do
        expect(reconciled).to eq("distributionUrl=foo\n")
      end
    end
  end
end
