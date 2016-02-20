worker: bundle exec sidekiq -q bump-repos_to_fetch_files_for -q bump-dependency_files_to_parse -q bump-dependencies_to_check -q bump-dependencies_to_update -q bump-updated_dependency_files -r ./app/init_sidekiq.rb -c 1
web: bundle exec rackup ./sidekiq_web.ru -p $PORT
