require 'logger'
require 'file/pid'
require 'rack/handler/mongrel2'

module Mongrel2
  class Pool
    attr_reader :uuid, :logger, :size, :workers, :klass

    DEFAULTS = {size: 1, pidfile: '/tmp/mongrel2-pool.pid', logfile: $stdout}

    def initialize uuid, klass, options = {}
      options = DEFAULTS.merge(options)
      File::Pid.new(options[:pidfile], Process.pid).run do
        @workers = []
        @uuid    = uuid
        @klass   = klass
        @size    = options[:size]
        @logger  = Logger.new(options[:logfile], 0)

        info "initialized with pool size #{size}"
      end
    end

    def self.run *args
      new(*args).run
      Process.waitall
    end

    def run
      trap_signals
      size.times { one_more }
    end

    def trap_signals
      Signal.trap('TTIN') { sleep 0.5; one_more }
      Signal.trap('TTOU') { sleep 0.5; one_less }
      Signal.trap('QUIT') { quit }
      Signal.trap('TERM') { kill }
      Signal.trap('INT')  { kill }
    end

    def one_more
      if pid = fork { Rack::Handler::Mongrel2.run klass, uuid: uuid }
        workers << pid
        info "started worker [#{pid}] - #{workers.size} workers in pool"
      end
    end

    def one_less
      if pid = workers.pop
        terminate_one(pid, 'QUIT')
      end
    end

    def terminate_one pid, signal
      info "terminating worker [#{pid}]"
      Process.kill(signal, pid)
      ensure_killed(pid, 0.1, 10)
    end

    def terminate_all signal
      workers.each {|pid| terminate_one(pid, signal) }
    end

    def quit
      terminate_all('QUIT')
    end

    def kill
      terminate_all('KILL')
    end

    def ensure_killed pid, wait, timeout
      while wait < timeout
        break if Process.kill(0, pid) rescue nil
        sleep(wait *= 2)
      end

      Process.kill('KILL', pid) rescue nil
    end

    def info  m; logger.info  "Mongrel2::Pool #{m}"; end
    def warn  m; logger.warn  "Mongrel2::Pool #{m}"; end
    def error m; logger.error "Mongrel2::Pool #{m}"; end
  end
end
