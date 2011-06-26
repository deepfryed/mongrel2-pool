require 'logger'
require 'file/pid'
require 'rack/handler/mongrel2'
require 'tempfile'
require 'fileutils'
require 'socket'

module Mongrel2
  class Pool

    DEFAULTS = {size: 1, pidfile: '/tmp/mongrel2-pool.pid', logfile: $stdout}

    def initialize uuid, klass, options = {}, &block
      options = DEFAULTS.merge(options)
      File::Pid.new(options[:pidfile], Process.pid).run do
        @workers    = []
        @uuid       = uuid
        @klass      = klass
        @after_fork = block
        @size       = options[:size]
        @isolate    = options[:isolate]
        @logger     = Logger.new(options[:logfile], 0)

        info "initialized with pool size #{size}"
      end
    end

    def self.run *args, &block
      new(*args, &block).run
      Process.waitall
    end

    def run
      trap_signals
      mongrel2_run if isolate
      size.times { one_more }
    end

    private
      attr_reader :uuid, :logger, :size, :workers, :klass, :isolate, :after_fork
      attr_reader :mongrel2_pid, :mongrel2_db

      def mongrel2_run
        @isolate = {} unless isolate.kind_of?(Hash)
        mongrel2_config do |file, server, host, port, error_log|
          @mongrel2_pid = fork { exec "exec mongrel2 #{file} #{server} 2>tmp/mongrel2.error.log" }

          if running?(mongrel2_pid, host, port)
            @mongrel2_db = file
            Process.detach(mongrel2_pid)
          else
            @mongrel2_pid = nil
            error         = mongrel2_error("[ERROR] unable to run mongrel2", error_log)

            FileUtils.rm_f(file)
            raise error
          end
        end
      end

      def mongrel2_error message, logfile
        File.open(logfile) do |file|
          file.seek(-1024, IO::SEEK_END)
          message + "\n\nERROR LOGS:\n" + file.read
        end
      end

      def mongrel2_config &block
        require 'sqlite3'
        file         = isolate[:config] ? mongrel2_setup_config : mongrel2_generate_config
        db           = SQLite3::Database.new(file)
        server       = isolate[:server] || db.execute('select uuid from server limit 1').first[0]
        result       = db.execute("select bind_addr, port, error_log from server where uuid = '#{server}'").first

        block.call(file, server, *result)

        ensure
          db.close if db
      end

      def mongrel2_setup_config
        file = Tempfile.new('mongrel2-pool')
        file.close

        if %r{\.conf$}.match(isolate[:config])
          unless system("m2sh load --config #{isolate[:config]} --db #{file.path}")
            raise "[ERROR] m2sh failed #{$?}"
          end
        else
          FileUtils.cp(isolate[:config], file.path)
        end

        file.path
      end

      def mongrel2_generate_config
        config = Tempfile.new('mongrel2-pool')
        config.write %Q{
          host = Host(name='localhost', routes={
            '/': Handler(
              send_spec   = 'tcp://127.0.0.1:9997',
              recv_spec   = 'tcp://127.0.0.1:9996',
              send_ident  = '#{uuid}',
              recv_ident  = ''
            )
          })

          main = Server(
            uuid         = 'mongrel2-pool-server',
            chroot       = '.',
            access_log   = '/tmp/mongrel2.access.log',
            error_log    = '/tmp/mongrel2.error.log',
            pid_file     = '/tmp/mongrel2.mongrel2.pid',
            default_host = 'localhost',
            name         = 'main',
            port         = 4000,
            hosts        = [host]
          )


          settings = {
            'zeromq.threads': 1
          }

          servers = [main]
        }

        file = Tempfile.new('mongrel2-pool')
        file.close
        config.close
        system "m2sh load --config #{config.path} --db #{file.path}"

        config.unlink
        FileUtils.mkpath('tmp')
        file.path
      end

      def running? pid, host, port
        20.times do
          alive = Process.kill(0, pid) rescue nil
          return false unless alive
          sleep 0.1
          return true if TCPSocket.new(host, port) rescue nil
        end
        return false
      end

      def trap_signals
        Signal.trap('TTIN') { sleep 0.5; one_more }
        Signal.trap('TTOU') { sleep 0.5; one_less }
        Signal.trap('QUIT') { quit }
        Signal.trap('TERM') { kill }
        Signal.trap('INT')  { kill }

        Signal.trap('CHLD') do
          unless halting?
            begin
              error "got SIGCHLD"
            rescue Errno::ECHILD => e
              error "got SIGCHLD and an exception #{e.message} - #{e.backtrace.join("\n")}"
            end
            (reap_dead && one_more) || mongrel2_respawn
          end
        end
      end

      def mongrel2_respawn
        if isolate && mongrel2_pid
          running = Process.kill(0, mongrel2_pid) rescue nil
          return if running
          FileUtils.rm_f(mongrel2_db)
          error "looks like mongrel2 died, spawning another one"
          mongrel2_run
        end
      end

      def reset_signal_handlers
        %w(TTIN TTOU QUIT TERM INT CHLD).each {|sig| Signal.trap(sig, 'DEFAULT')}
      end

      def reap_dead pid = nil
        if pid
          workers.delete(pid)
        else
          reaped = 0
          workers.each do |pid|
            running = Process.kill(0, pid) rescue nil
            next if running
            info "reaping worker #{pid}"
            workers.delete(pid)
            reaped += 1
          end
          reaped > 0
        end
      end

      def one_more
        if pid = fork_worker
          workers << pid
          info "started worker [#{pid}] - #{workers.size} workers in pool"
        end
      end

      def fork_worker
        fork do
          $0 = "mongrel2-pool/#{uuid} [#{Process.pid}]"
          reset_signal_handlers
          after_fork.call(Process.pid) if after_fork
          Rack::Handler::Mongrel2.run(klass, uuid: uuid)
        end
      end

      def one_less
        if pid = workers.pop
          terminate_one(pid, 'QUIT')
        end
      end

      def terminate_one pid, signal
        info "terminating worker [#{pid}]"
        Process.kill(signal, pid) rescue nil
        ensure_killed(pid, 0.1, 10)
      end

      def terminate_all signal
        workers.each {|pid| terminate_one(pid, signal) }
        workers.clear
      end

      def quit
        @halting = true
        terminate_all('QUIT')
        if mongrel2_pid
          info "terminating mongrel2 [#{mongrel2_pid}]"
          Process.kill('QUIT', mongrel2_pid)
          FileUtils.rm_f(mongrel2_db)
        end
        exit
      end

      def kill
        @halting = true
        terminate_all('KILL')
        if mongrel2_pid
          info "terminating mongrel2 [#{mongrel2_pid}]"
          Process.kill('TERM', mongrel2_pid) rescue nil
          FileUtils.rm_f(mongrel2_db)
        end
        exit
      end

      def halting?
        !!@halting
      end

      def ensure_killed pid, wait, timeout
        while wait < timeout
          Process.wait(pid, Process::WNOHANG) rescue nil
          running = Process.kill(0, pid) rescue nil
          break unless running
          sleep(wait *= 2)
        end

        Process.kill('KILL', pid) rescue nil
      end

      def info  m; logger.info  "Mongrel2::Pool #{m}"; end
      def warn  m; logger.warn  "Mongrel2::Pool #{m}"; end
      def error m; logger.error "Mongrel2::Pool #{m}"; end
  end
end
