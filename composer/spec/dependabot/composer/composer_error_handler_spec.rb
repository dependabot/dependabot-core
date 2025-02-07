# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/update_checker/version_resolver"

RSpec.describe Dependabot::Composer::ComposerErrorHandler do
  subject(:error_handler) { described_class.new }

  let(:error) { instance_double(Dependabot::SharedHelpers::HelperSubprocessFailed, message: error_message) }

  context "when the error message returns an empty response from server" do
    let(:error_message) do
      "curl error 52 while downloading https://rep.com: Empty reply from server"
    end

    it "raises a PrivateSourceBadResponse error with the correct message" do
      expect do
        error_handler.handle_composer_error(error)
      end.to raise_error(Dependabot::PrivateSourceBadResponse)
    end
  end

  context "when the error message returns an private source auth error" do
    let(:error_message) do
      "Could not authenticate against composer.registry.com"
    end

    it "raises a PrivateSourceAuthenticationFailure error with the correct message" do
      expect do
        error_handler.handle_composer_error(error)
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  context "when the error message returns an private source HTTP 403 error" do
    let(:error_message) do
      "The 'https://el.typo.com/packages.json' URL could not be accessed (HTTP 403): HTTP/1.1 403"
    end

    it "raises a PrivateSourceAuthenticationFailure error with the correct message" do
      expect do
        error_handler.handle_composer_error(error)
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  context "when the error message returns an private source bad response" do
    let(:error_message) do
      "The \"https://repo.magento.com/p/magento/module.json\" file could not be downloaded"
    end

    it "raises a PrivateSourceAuthenticationFailure error with the correct message" do
      expect do
        error_handler.handle_composer_error(error)
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  context "when the error message returns an private source bad response" do
    let(:error_message) do
      "The \"?pagelen=100&fields=values.name%2C\" file could not be downloaded"
    end

    it "raises a PrivateSourceAuthenticationFailure error with the correct message" do
      expect do
        error_handler.handle_composer_error(error)
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  context "when the error message returns invalid requirement error" do
    let(:error_message) do
      "require.PHPOffice/PHPExcel is invalid, it should not contain uppercase characters." \
        " Please use phpoffice/phpexcel instead."
    end

    it "raises a DependencyFileNotResolvable error with the correct message" do
      expect do
        error_handler.handle_composer_error(error)
      end.to raise_error(Dependabot::DependencyFileNotResolvable)
    end
  end
end
