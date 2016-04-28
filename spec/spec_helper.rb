$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "active_support/notifications"
require "kafka"
require "dotenv"
require "logger"
require "rspec-benchmark"

Dotenv.load

LOGGER = Logger.new(ENV.key?("LOG_TO_STDERR") ? $stderr : StringIO.new)
LOGGER.level = Logger.const_get(ENV.fetch("LOG_LEVEL", "INFO"))

module SpecHelpers
  def generate_topic_name
    @@topic_number ||= 0
    @@topic_number += 1

    "topic-#{@@topic_number}"
  end

  def create_random_topic(*args)
    topic = generate_topic_name
    create_topic(topic, *args)
    topic
  end

  def create_topic(*args)
    cluster.create_topic(*args)
  end

  def cluster
    KAFKA_CLUSTER
  end
end

RSpec.configure do |config|
  config.filter_run_excluding functional: true, performance: true, fuzz: true
  config.include RSpec::Benchmark::Matchers
  config.include SpecHelpers
end

ActiveSupport::Notifications.subscribe(/.*\.kafka$/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  LOGGER.debug "Instrumentation event `#{event.name}`: #{event.payload.inspect}"
end
