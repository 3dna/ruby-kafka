describe Kafka::Connection do
  let(:logger) { Logger.new(LOG) }
  let(:host) { "127.0.0.1" }
  let(:server) { TCPServer.new(host, 0) }
  let(:port) { server.addr[1] }

  let(:connection) {
    Kafka::Connection.new(
      host: host,
      port: port,
      client_id: "test",
      logger: logger,
    )
  }

  before do
    broker = Thread.start { FakeServer.new(server).run }
    broker.abort_on_exception = true
  end

  class FakeServer
    def initialize(server)
      @server = server
    end

    def run
      loop do
        client = @server.accept

        loop do
          request_bytes = Kafka::Protocol::Decoder.new(client).bytes
          request_decoder = Kafka::Protocol::Decoder.new(StringIO.new(request_bytes))

          api_key = request_decoder.int16
          api_version = request_decoder.int16
          correlation_id = request_decoder.int32
          client_id = request_decoder.string

          message = request_decoder.string

          response = StringIO.new
          response_encoder = Kafka::Protocol::Encoder.new(response)
          response_encoder.write_int32(correlation_id)
          response_encoder.write_string(message)

          encoder = Kafka::Protocol::Encoder.new(client)
          encoder.write_bytes(response.string)
        end

        client.close
      end
    end
  end

  describe "#request" do
    let(:api_key) { 5 }
    let(:request) { double(:request) }
    let(:response_decoder) { double(:response_decoder) }

    before do
      allow(request).to receive(:encode) {|encoder| encoder.write_string("hello!") }

      allow(response_decoder).to receive(:decode) {|decoder|
        decoder.string
      }
    end

    it "sends requests to a broker and reads back the response" do
      response = connection.request(api_key, request, response_decoder)

      expect(response).to eq "hello!"
    end

    it "skips responses to previous requests" do
      # By passing nil as the final argument we're telling Connection that we're
      # not expecting a response, so it won't read one. However, the fake broker
      # *is* writing a response, so we'll get that the next time we read a response,
      # causing a mismatch. This simulates the client killing the connection due
      # to e.g. a timeout, then resuming with a new request -- the old response
      # still sits in the connection waiting to be read.
      connection.request(api_key, request, nil)

      allow(request).to receive(:encode) {|encoder| encoder.write_string("goodbye!") }
      response = connection.request(api_key, request, response_decoder)

      expect(response).to eq "goodbye!"
    end
  end
end
