# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Composer do
  it_behaves_like "it registers the required classes", "composer"

  it "has the same binary version of composer 2 installed as specified in the native helper" do
    # Hello fellow composer updater! If you're reading this, you're probably
    # wondering why this test is failing. Well, it's because the version of the
    # natively installed composer binary is different to the version specified
    # in the native helper.
    #
    # If you've updated the composer version in
    # composer/helpers/v2/composer.lock, you also need to bump it in the
    # Dockerfile.

    expect(helper_composer_version(major_version: "v2")).to eq(native_composer_version(major_version: "v2"))
  end

  it "has the same binary version of composer 1 installed as specified in the native helper" do
    expect(helper_composer_version(major_version: "v1")).to eq(native_composer_version(major_version: "v1"))
  end

  private

  def helper_composer_version(major_version:)
    composer_lock = File.read(
      File.join(Dependabot::Composer::NativeHelpers.composer_helpers_dir, major_version, "composer.lock")
    )
    JSON.parse(composer_lock)["packages"].find { |p| p["name"] == "composer/composer" }["version"]
  end

  def native_composer_version(major_version:)
    native_composer_output = if major_version == "v1"
                               Dependabot::SharedHelpers.run_shell_command("composer1 --version")
                             else
                               Dependabot::SharedHelpers.run_shell_command("composer --version")
                             end
    native_composer_output.match(/composer\s+version\s+(\d+\.\d+\.\d+)/i).captures.first
  end
end
