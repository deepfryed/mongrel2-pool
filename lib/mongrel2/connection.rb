require 'zmq'
require 'mongrel2/request'
require 'mongrel2/response'

module Mongrel2
  class Connection
    def context
      @context ||= ZMQ::Context.new(1)
    end

    def initialize uuid, sub, pub
      @uuid, @sub, @pub = uuid, sub, pub

      # Connect to receive requests
      @receiver = context.socket(ZMQ::PULL)
      @receiver.connect(sub)

      # Connect to send responses
      @responder = context.socket(ZMQ::PUB)
      @responder.connect(pub)
      @responder.setsockopt(ZMQ::IDENTITY, uuid)

      # Shutdown queue
      @shutdown = context.socket(ZMQ::PULL)
      @shutdown.connect(shutdown_queue)
    end

    def shutdown_queue
      "ipc://shutdown_queue_#{hash.abs}"
    end

    def receive
      queue = ZMQ.select([@receiver, @shutdown])
      if queue[0][0] == @shutdown
        close
      else
        msg = @receiver.recv(0)
        msg.nil? ? nil : Request.parse(msg)
      end
    end

    def reply req, body, status = 200, headers = {}
      resp = Response.new(@responder)
      resp.send_http(req, body, status, headers)
      resp.close(req) if req.close?
    end

    def close
      @responder.close
      @receiver.close
       @shutdown.close
      context.close rescue nil
    end
  end
end
