$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require "kafka"

KAFKA_CLIENT_CERT = ENV.fetch("KAFKA_CLIENT_CERT")
KAFKA_CLIENT_CERT_KEY = ENV.fetch("KAFKA_CLIENT_CERT_KEY")
KAFKA_SERVER_CERT = ENV.fetch("KAFKA_SERVER_CERT")
KAFKA_URL = ENV.fetch("KAFKA_URL")
KAFKA_BROKERS = KAFKA_URL.gsub("kafka+ssl://", "").split(",")
KAFKA_TOPIC = "test-messages"

NUM_THREADS = 4

queue = Queue.new

threads = NUM_THREADS.times.map do
  Thread.new do
    logger = Logger.new($stderr)
    logger.level = Logger::INFO

    kafka = Kafka.new(
      seed_brokers: KAFKA_BROKERS,
      logger: logger,
      connect_timeout: 30,
      socket_timeout: 30,
      ssl_client_cert: KAFKA_CLIENT_CERT,
      ssl_client_cert_key: KAFKA_CLIENT_CERT_KEY,
      ssl_ca_cert: KAFKA_SERVER_CERT,
    )

    consumer = kafka.consumer(group_id: "firehose")
    consumer.subscribe(KAFKA_TOPIC)

    begin
      i = 0
      consumer.each_message do |message|
        i += 1

        if i % 100 == 0
          queue << i
          i = 0
        end
      end
    ensure
      consumer.shutdown
    end
  end
end

threads.each {|t| t.abort_on_exception = true }

received_messages = 0

loop do
  received_messages += queue.pop
  puts "===> Received #{received_messages} messages"
end
