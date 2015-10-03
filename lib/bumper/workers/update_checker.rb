require "shoryuken"
require "bumper/workers"
require "bumper/dependency"
require "bumper/update_checkers/ruby_update_checker"

class Workers::UpdateChecker
  include Shoryuken::Worker

  shoryuken_options(
    queue: "bump-dependencies_to_check",
    body_parser: :json,
    auto_delete: true,
  )

  def perform(sqs_message, body)
    update_checker_class = update_checker_for(body["repo"]["language"])
    dependency = Dependency.new(
      name: body["dependency"]["name"],
      version: body["dependency"]["version"],
    )

    update_checker = update_checker_class.new(dependency)
    send_update_notification if update_checker.needs_update?
  end

  private

  def send_update_notification
    # TODO write a message into the next queue
    `curl -s -d '#{dependency.name} needs update' http://requestb.in/za3prvza`
  end

  def update_checker_for(language)
    case language
    when "ruby" then UpdateCheckers::RubyUpdateChecker
    else raise "Invalid language #{language}"
    end
  end
end
