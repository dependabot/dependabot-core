bump
====
```
dependency_file_fetcher:
  inputs:
    repos:
      name
      language
​
dependency_file_parser:
  inputs:
    repo:
      name
      language
    dependency_files:
      name
      contents
​
update_checker:
  inputs:
    repo:
      name
      language
    dependency_files:
      name
      contents
    dependency:
      name
      version
​
dependency_file_updater:
  inputs:
    repo:
      name
      language
    dependency_files:
      name
      contents
    updated_dependency:
      name
      version
​
pull_request_creator:
  inputs:
    repo:
      name
      language
    updated_dependency_files:
      name
      contents
    updated_dependency:
      name
      version
```

# Development

Install RabbitMQ
```
cp dummy-env .env
brew install rabbitmq
rabbitmqctl add_vhost guest
rabbitmqctl set_permissions -p guest guest ".*" ".*" ".*"
```
