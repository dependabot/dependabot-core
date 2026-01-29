# At the top of the file, add requires:
require_relative "message_builder/components/title_builder"
require_relative "message_builder/components/body_builder"
require_relative "message_builder/components/commit_message_builder"
require_relative "message_builder/strategies/single_update"
require_relative "message_builder/strategies/group_update"
require_relative "message_builder/strategies/multi_ecosystem"

# Replace the pr_name method:
sig { returns(String) }
def pr_name
  Components::TitleBuilder.new(
    base_title: title_strategy.base_title,
    prefixer: pr_name_prefixer
  ).build
end

# Add private method for strategy selection:
private

sig { returns(Strategies::Base) }
def title_strategy
  if dependency_group
    Strategies::GroupUpdate.new(
      dependencies: dependencies,
      group_name: T.must(dependency_group).name,
      directory: files.first&.directory
    )
  else
    Strategies::SingleUpdate.new(
      dependency: T.must(dependencies.first),
      library: library?,
      directory: files.first&.directory
    )
  end
end