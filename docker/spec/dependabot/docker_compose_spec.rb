# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker_compose"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::DockerCompose do
  it_behaves_like "it registers the required classes", "docker_compose"
end
