require 'hutch'
require 'dotenv'
Dotenv.load
Hutch::Config.set(:mq_host, ENV['AMQP_HOST'])
Hutch::Config.set(:mq_api_host, ENV['AMQP_API_HOST'])
Hutch::Config.set(:mq_api_port, ENV['AMQP_API_PORT'])
Hutch::Config.set(:mq_vhost, ENV['AMQP_VHOST'])
Hutch::Config.set(:mq_api_ssl, ENV['AMQP_SSL_FLAG'] == '-s')
Hutch::Config.set(:mq_username, ENV['AMQP_USERNAME'])
Hutch::Config.set(:mq_password, ENV['AMQP_PASSWORD'])
Hutch.connect
Hutch.publish("bump.repos_to_fetch_files_for",
              "repo" => { "language" => "ruby",
                          "name" => "gocardless/bump-test" })
