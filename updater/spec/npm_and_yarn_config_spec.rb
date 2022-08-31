# frozen_string_literal: true

require "spec_helper"

RSpec.describe "npm and yarn config" do
  # NOTE: This comes from config/.npmrc
  it "contains a valid .npmrc config file" do
    npm_result = `npm config list`
    # Output from yarn config set
    expect(npm_result).to include("audit = false")
    expect(npm_result).to include(
      "cafile = \"/usr/local/share/ca-certificates/dbot-ca.crt\""
    )
    expect(npm_result).to include("dry-run = true")
    expect(npm_result).to include("ignore-scripts = true")
  end

  # NOTE: This comes from config/.yarnrc
  it "contains a valid .yarnrc config file" do
    yarn_config = File.read("/home/dependabot/.yarnrc")
    # Output from yarn config set
    expect(yarn_config).to include(
      "cafile \"/etc/ssl/certs/ca-certificates.crt\""
    )
  end
end
