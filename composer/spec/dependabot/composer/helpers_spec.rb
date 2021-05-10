# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer/helpers"

RSpec.describe Dependabot::Composer::Helpers do
  describe ".composer_version" do
    let(:composer_v2_content) do
      <<~JSON
        {
          "name": "valid/name",
          "version": "3.1.7",
          "dist": {
            "url": "https://www.example.net/files/3.1.7.zip",
            "type": "zip"
          },
          "require": {
            "monolog/monolog" : "1.0.1",
            "symfony/polyfill-mbstring": "1.0.1",
            "php": "*",
            "lib-foo": "*",
            "ext-bar": "*"
          }
        }
      JSON
    end

    let(:composer_v1_content) do
      <<~JSON
        {
          "name": "valid/name",
          "version": "3.1.7",
          "dist": {
            "url": "https://www.example.net/files/3.1.7.zip",
            "type": "zip"
          },
          "require": {
            "monolog/monolog" : "1.0.1",
            "symfony/polyfill-mbstring": "1.0.1",
            "php": "*",
            "invalid-package-name": "*"
          }
        }
      JSON
    end

    it "uses v2 for a manifest that specifies a platform dependency without lockfile" do
      composer_json = JSON.parse(composer_v2_content)

      expect(described_class.composer_version(composer_json)).to eq("v2")
    end

    it "uses v1 when one of the packages has an invalid name" do
      composer_json = JSON.parse(composer_v1_content)

      expect(described_class.composer_version(composer_json)).to eq("v1")
    end
  end
end
