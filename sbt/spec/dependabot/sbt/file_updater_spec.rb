# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/sbt/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Sbt::FileUpdater do
  it_behaves_like "a dependency file updater"
end
