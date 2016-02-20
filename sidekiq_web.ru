require 'sidekiq'
require 'prius'
require 'sidekiq/web'

Prius.load(:auth_username)
Prius.load(:auth_password)

Sidekiq.configure_client { |config| config.redis = { :size => 1 } }

use Rack::Auth::Basic, "Restricted Area" do |username, password|
  [username, password] == [Prius.get(:auth_username), Prius.get(:auth_password)]
end

run Sidekiq::Web
