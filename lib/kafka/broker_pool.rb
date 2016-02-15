require "kafka/broker"

module Kafka
  class BrokerPool
    def initialize(client_id:, connect_timeout: nil, socket_timeout: nil, logger:)
      @client_id = client_id
      @connect_timeout = connect_timeout
      @socket_timeout = socket_timeout
      @logger = logger
      @brokers = {}
    end

    def connect(host, port, node_id: nil)
      return @brokers.fetch(node_id) if @brokers.key?(node_id)

      broker = Broker.connect(
        host: host,
        port: port,
        node_id: node_id,
        client_id: @client_id,
        connect_timeout: @connect_timeout,
        socket_timeout: @socket_timeout,
        logger: @logger,
      )

      @brokers[node_id] = broker unless node_id.nil?

      broker
    end

    def close
      @brokers.each do |id, broker|
        @logger.info "Disconnecting broker #{id}"
        broker.disconnect
      end
    end
  end
end
