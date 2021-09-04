Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URI"), password: ENV.fetch("REDIS_PASSWORD") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URI"), password: ENV.fetch("REDIS_PASSWORD") }
end