require 'rack'
require 'stringio'
require 'mongrel2/connection'

module Rack
  module Handler
    class Mongrel2
      DEFAULTS = {
        recv: 'tcp://127.0.0.1:9997' || ENV['RACK_MONGREL2_RECV'],
        send: 'tcp://127.0.0.1:9996' || ENV['RACK_MONGREL2_SEND'],
        uuid: ENV['RACK_MONGREL2_UUID']
      }

      class << self

        def run app, options = {}
          options = DEFAULTS.merge(options)
          raise ArgumentError.new('Must specify an :uuid or set RACK_MONGREL2_UUID') if options[:uuid].nil?

          running  = true
          conn     = ::Mongrel2::Connection.new(options[:uuid], options[:recv], options[:send])
          handler  = Thread.new do
            while running
              req = conn.receive rescue nil

              next  if req.nil? || req.disconnect?
              break if !running

              script_name = ENV['RACK_RELATIVE_URL_ROOT'] || req.headers['PATTERN'].split('(', 2).first.gsub(/\/$/, '')

              env = {
                'rack.version'      => Rack::VERSION,
                'rack.url_scheme'   => 'http', # Only HTTP for now
                'rack.input'        => StringIO.new(req.body),
                'rack.errors'       => $stderr,
                'rack.multithread'  => true,
                'rack.multiprocess' => true,
                'rack.run_once'     => false,
                'mongrel2.pattern'  => req.headers['PATTERN'],
                'REQUEST_METHOD'    => req.headers['METHOD'],
                'SCRIPT_NAME'       => script_name,
                'PATH_INFO'         => req.headers['PATH'].gsub(script_name, ''),
                'QUERY_STRING'      => req.headers['QUERY'] || ''
              }

              env['SERVER_NAME'], env['SERVER_PORT'] = req.headers['host'].split(':', 2)
              req.headers.each do |key, val|
                unless key =~ /content_(type|length)/i
                  key = "HTTP_#{key.upcase.gsub('-', '_')}"
                end
                env[key] = val
              end

              begin
                body = ''
                status, headers, rack_response = app.call(env)
                rack_response.each { |b| body << b }
                conn.reply(req, body, status, headers)
              rescue Exception => e
                $stderr.puts e.message
                conn.reply(req, '500 Internal Server Error', 500, {})
              end
            end
        end

        # thanks to, http://www.ioncannon.net/programming/1384/example-mongrel2-handler-in-ruby/
        %w(INT TERM QUIT HUP).each do |name|
          Signal.trap(name) do
            running = false
            context = ZMQ::Context.new(1)
            queue   = context.socket(ZMQ::PUSH)

            queue.bind("ipc://shutdown_queue")
            queue.send("shutdown")

            queue.close
            context.close

            handler.kill if handler.alive?
            conn.close
          end
        end

        handler.join
        ensure
          conn.close if conn.respond_to?(:close)
        end
      end
    end
  end
end
