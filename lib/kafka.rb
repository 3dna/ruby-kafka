require "kafka/version"
require "kafka/cluster"
require "kafka/producer"

module Kafka
  Error = Class.new(StandardError)
  CorruptMessage = Class.new(Error)
  UnknownError = Class.new(Error)
  OffsetOutOfRange = Class.new(Error)
  UnknownTopicOrPartition = Class.new(Error)
  InvalidMessageSize = Class.new(Error)
  LeaderNotAvailable = Class.new(Error)
  NotLeaderForPartition = Class.new(Error)
  RequestTimedOut = Class.new(Error)

  def self.new(**options)
    Cluster.new(**options)
  end
end
