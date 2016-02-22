class FakeSyncProducer
  def initialize(mutex)
    @mutex = mutex
  end

  def produce(*args)
    @mutex.lock
  end

  def deliver_messages
  end

  def shutdown
  end
end

describe Kafka::AsyncProducer do
  describe "#produce" do
    it "raises BufferOverflow if the queue exceeds the defined max size" do
      # The sync producer will be blocked trying to grab the mutex.
      mutex = Mutex.new
      mutex.lock

      sync_producer = FakeSyncProducer.new(mutex)

      producer = Kafka::AsyncProducer.new(
        sync_producer: sync_producer,
        max_queue_size: 2,
      )

      expect {
        3.times do
          producer.produce("hello", topic: "greetings")
        end
      }.to raise_exception(Kafka::BufferOverflow)
    end
  end

  describe "#deliver_messages" do
    it "handles when the sync producer fails to deliver messages" do
      sync_producer = double(:sync_producer, shutdown: nil, produce: nil)

      producer = Kafka::AsyncProducer.new(
        sync_producer: sync_producer,
      )

      producer.produce("hello", topic: "greetings")

      allow(sync_producer).to receive(:deliver_messages).and_raise(Kafka::DeliveryFailed)

      producer.deliver_messages
      producer.shutdown
    end
  end
end
