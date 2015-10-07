require "hutch"
Hutch.connect
Hutch.publish("bump.repos_to_fetch_files_for",
              "repo" => { "language" => "ruby",
                          "name" => "gocardless/bump-test" })
