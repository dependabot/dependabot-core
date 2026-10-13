# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/shared/maven_settings"

RSpec.describe Dependabot::Maven::Shared::MavenSettings do
  describe ".xml" do
    it "keeps only the proxy block when there is nothing to add" do
      doc = Nokogiri::XML(described_class.xml)

      expect(doc.at_xpath("/settings/proxies/proxy/host").text).to eq("${env.PROXY_HOST}")
      expect(doc.at_xpath("/settings/mirrors")).to be_nil
      expect(doc.at_xpath("/settings/profiles")).to be_nil
    end

    it "can leave out the proxy block" do
      doc = Nokogiri::XML(described_class.xml(proxy: false))

      expect(doc.at_xpath("/settings/proxies")).to be_nil
    end

    it "adds a mirror and registries as repositories and plugin repositories in an active profile" do
      mirror = described_class::Mirror.new(
        id: "dependabot-registry-mirror", url: "https://base.example.test/maven", mirror_of: "central"
      )
      doc = Nokogiri::XML(
        described_class.xml(
          mirror: mirror,
          repository_urls: ["https://one.example.test/maven", "https://two.example.test/maven"]
        )
      )

      expect(doc.at_xpath("/settings/mirrors/mirror/mirrorOf").text).to eq("central")
      expect(doc.at_xpath("/settings/mirrors/mirror/url").text).to eq("https://base.example.test/maven")
      expect(doc.xpath("//profile/repositories/repository/url").map(&:text))
        .to eq(["https://one.example.test/maven", "https://two.example.test/maven"])
      expect(doc.xpath("//profile/pluginRepositories/pluginRepository/url").map(&:text))
        .to eq(["https://one.example.test/maven", "https://two.example.test/maven"])
      expect(doc.xpath("//profile/repositories/repository/id").map(&:text))
        .to eq(%w(dependabot-registry-1 dependabot-registry-2))
      expect(doc.at_xpath("/settings/activeProfiles/activeProfile").text)
        .to eq(doc.at_xpath("//profile/id").text)
    end
  end

  describe ".with_file" do
    it "yields a path to the settings and returns the block result" do
      result = described_class.with_file(repository_urls: ["https://one.example.test/maven"]) do |path|
        File.read(path)
      end

      expect(result).to eq(described_class.xml(repository_urls: ["https://one.example.test/maven"]))
    end

    it "removes the file afterwards" do
      path = described_class.with_file { |settings_path| settings_path }

      expect(File.exist?(path)).to be(false)
    end

    it "removes the file when the block raises" do
      path = nil

      expect do
        described_class.with_file do |settings_path|
          path = settings_path
          raise "boom"
        end
      end.to raise_error("boom")
      expect(File.exist?(path)).to be(false)
    end
  end

  describe ".proxy_env" do
    it "sets the proxy host from HTTPS_PROXY" do
      stub_const("ENV", ENV.to_h.merge("HTTPS_PROXY" => "http://proxy.example.test:1080"))

      expect(described_class.proxy_env).to eq("PROXY_HOST" => "proxy.example.test")
    end

    it "is empty when HTTPS_PROXY is not set" do
      stub_const("ENV", ENV.to_h.except("HTTPS_PROXY"))

      expect(described_class.proxy_env).to eq({})
    end
  end
end
