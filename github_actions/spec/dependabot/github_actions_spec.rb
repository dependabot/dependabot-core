# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::GithubActions do
  it_behaves_like "it registers the required classes", "github_actions"
end
