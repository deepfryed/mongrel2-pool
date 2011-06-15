require_relative 'helper'
require 'stringio'
require 'open-uri'

describe 'rack application' do
  before do
    @app = Class.new do
      def self.call env
        [200, {'Content-Type' => 'text/plain'}, ['hello world', $/]]
      end
    end
  end

  after do
    # wait for server to quit.
    sleep 1
  end

  it 'runs fine' do
    run_app(@app) do |pid, io|
      # wait till mongrel2 comes up.
      sleep 0.5
      res = open('http://127.0.0.1:4000').read
      assert_match %r{hello world}, res
      assert_match %r{1 workers in pool}i, io.rewind && io.read
    end
  end

  it 'traps TTIN' do
    run_app(@app) do |pid, io|
      # wait till mongrel2 comes up.
      sleep 0.5
      res  = open('http://127.0.0.1:4000').read
      size = io.rewind && io.read.size

      # send a signal.
      Process.kill('TTIN', pid)

      # wait for log message.
      timeout(5) do
        sleep 0.1 while (io.rewind && io.read.size == size)
        assert_match %r{2 workers in pool}i, io.rewind && io.read
      end
    end
  end
end
