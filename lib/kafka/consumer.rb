require "kafka/consumer_group"
require "kafka/offset_manager"
require "kafka/fetch_operation"

module Kafka

  # @note This code is still alpha level. Don't use this for anything important.
  #   The API may also change without warning.
  #
  # A client that consumes messages from a Kafka cluster in coordination with
  # other clients.
  #
  # A Consumer subscribes to one or more Kafka topics; all consumers with the
  # same *group id* then agree on who should read from the individual topic
  # partitions. When group members join or leave, the group synchronizes,
  # making sure that all partitions are assigned to a single member, and that
  # all members have some partitions to read from.
  #
  # ## Example
  #
  # A simple producer that simply writes the messages it consumes to the
  # console.
  #
  #     require "kafka"
  #
  #     kafka = Kafka.new(seed_brokers: ["kafka1:9092", "kafka2:9092"])
  #
  #     # Create a new Consumer instance in the group `my-group`:
  #     consumer = kafka.consumer(group_id: "my-group")
  #
  #     # Subscribe to a Kafka topic:
  #     consumer.subscribe("messages")
  #
  #     begin
  #       # Loop forever, reading in messages from all topics that have been
  #       # subscribed to.
  #       consumer.each_message do |message|
  #         puts message.topic
  #         puts message.partition
  #         puts message.key
  #         puts message.value
  #         puts message.offset
  #       end
  #     ensure
  #       # Make sure to shut down the consumer after use. This lets
  #       # the consumer notify the Kafka cluster that it's leaving
  #       # the group, causing a synchronization and re-balancing of
  #       # the group.
  #       consumer.shutdown
  #     end
  #
  class Consumer

    # Creates a new Consumer.
    #
    # @param cluster [Kafka::Cluster]
    # @param logger [Logger]
    # @param group_id [String] the id of the group that the consumer should join.
    # @param session_timeout [Integer] the interval between consumer heartbeats,
    #   in seconds.
    def initialize(cluster:, logger:, group_id:, session_timeout: 30)
      @cluster = cluster
      @logger = logger
      @group_id = group_id
      @session_timeout = session_timeout

      @group = ConsumerGroup.new(
        cluster: cluster,
        logger: logger,
        group_id: group_id,
        session_timeout: @session_timeout,
      )

      @offset_manager = OffsetManager.new(
        group: @group,
        logger: @logger,
      )
    end

    # Subscribes the consumer to a topic.
    #
    # Typically you either want to start reading messages from the very
    # beginning of the topic's partitions or you simply want to wait for new
    # messages to be written. In the former case, set `default_offsets` to
    # `:earliest` (the default); in the latter, set it to `:latest`.
    #
    # @param topic [String] the name of the topic to subscribe to.
    # @param default_offset [Symbol] whether to start from the beginning or the
    #   end of the topic's partitions.
    # @return [nil]
    def subscribe(topic, default_offset: :earliest)
      @group.subscribe(topic)
      @offset_manager.set_default_offset(topic, default_offset)

      nil
    end

    # Fetches and enumerates the messages in the topics that the consumer group
    # subscribes to.
    #
    # Each message is yielded to the provided block. If the block returns
    # without raising an exception, the message will be considered successfully
    # processed. At regular intervals the offset of the most recent successfully
    # processed message in each partition will be committed to the Kafka
    # offset store. If the consumer crashes or leaves the group, the group member
    # that is tasked with taking over processing of these partitions will resume
    # at the last committed offsets.
    #
    # @yieldparam message [Kafka::FetchedMessage] a message fetched from Kafka.
    # @return [nil]
    def each_message
      loop do
        begin
          batch = fetch_batch

          batch.each do |message|
            Instrumentation.instrument("process_message.consumer.kafka") do |notification|
              notification.update(
                topic: message.topic,
                partition: message.partition,
                offset: message.offset,
                key: message.key,
                value: message.value,
              )

              yield message
            end

            send_heartbeat_if_necessary
            mark_message_as_processed(message)
          end
        rescue ConnectionError => e
          @logger.error "Connection error while fetching messages: #{e}"
        else
          @offset_manager.commit_offsets unless batch.nil? || batch.empty?
        end
      end
    end

    # Shuts down the consumer.
    #
    # In order to quickly have the consumer group re-balance itself, it's
    # important that members explicitly tell Kafka when they're leaving.
    # Therefore it's a good idea to call this method whenever your consumer
    # is about to quit. If this method is not called, it may take up to
    # the amount of time defined by the `session_timeout` parameter for
    # Kafka to realize that this consumer is no longer present and trigger
    # a group re-balance. In that period of time, the partitions that used
    # to be assigned to this consumer won't be processed.
    #
    # @return [nil]
    def shutdown
      @offset_manager.commit_offsets
      @group.leave
    end

    private

    def fetch_batch
      @group.join unless @group.member?

      @logger.debug "Fetching a batch of messages"

      assigned_partitions = @group.assigned_partitions

      send_heartbeat_if_necessary

      raise "No partitions assigned!" if assigned_partitions.empty?

      operation = FetchOperation.new(
        cluster: @cluster,
        logger: @logger,
        min_bytes: 1,
        max_wait_time: 5,
      )

      assigned_partitions.each do |topic, partitions|
        partitions.each do |partition|
          offset = @offset_manager.next_offset_for(topic, partition)

          @logger.debug "Fetching from #{topic}/#{partition} starting at offset #{offset}"

          operation.fetch_from_partition(topic, partition, offset: offset)
        end
      end

      messages = operation.execute

      @logger.debug "Fetched #{messages.count} messages"

      messages
    end

    # Sends a heartbeat if it would be necessary in order to avoid getting
    # kicked out of the consumer group.
    #
    # Each consumer needs to send a heartbeat with a frequency defined by
    # `session_timeout`.
    #
    def send_heartbeat_if_necessary
      @last_heartbeat ||= Time.at(0)

      if @last_heartbeat <= Time.now - @session_timeout + 2
        @group.heartbeat
        @last_heartbeat = Time.now
      end
    end

    def mark_message_as_processed(message)
      @offset_manager.mark_as_processed(message.topic, message.partition, message.offset)
    end
  end
end
