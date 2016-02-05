require "kafka/broker_pool"
require "kafka/producer"

module Kafka
  class Client
    DEFAULT_CLIENT_ID = "ruby-kafka"
    DEFAULT_LOGGER = Logger.new("/dev/null")

    # Initializes a new Kafka client.
    #
    # @param seed_brokers [Array<String>] the list of brokers used to initialize
    #   the client.
    #
    # @param client_id [String] the identifier for this application.
    #
    # @param logger [Logger]
    #
    # @param connect_timeout [Integer, nil] the timeout setting for connecting
    #   to brokers. See {BrokerPool#initialize}.
    #
    # @param socket_timeout [Integer, nil] the timeout setting for socket
    #   connections. See {BrokerPool#initialize}.
    #
    # @return [Client]
    def initialize(seed_brokers:, client_id: DEFAULT_CLIENT_ID, logger: DEFAULT_LOGGER, connect_timeout: nil, socket_timeout: nil)
      @logger = logger

      @broker_pool = BrokerPool.new(
        seed_brokers: seed_brokers,
        client_id: client_id,
        logger: logger,
        connect_timeout: connect_timeout,
        socket_timeout: socket_timeout,
      )
    end

    # Builds a new producer.
    #
    # `options` are passed to {Producer#initialize}.
    #
    # @see Producer#initialize
    # @return [Producer] the Kafka producer.
    def get_producer(**options)
      Producer.new(broker_pool: @broker_pool, logger: @logger, **options)
    end

    # Lists all topics in the cluster.
    #
    # @return [Array<String>] the list of topic names.
    def topics
      @broker_pool.topics
    end

    def close
      @broker_pool.shutdown
    end
  end
end
