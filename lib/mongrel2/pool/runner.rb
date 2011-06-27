require 'rack'
require 'mongrel2-pool'
require 'mongrel2/pool/config'

class Mongrel2::Pool
  class Runner
    attr_reader :instance

    def initialize rackup_file, config_file
      app        = Rack::Builder.parse_file(rackup_file)
      config     = Mongrel2::Pool::Config.parse_file(config_file)
      after_fork = config.delete(:after_fork)
      @instance  = Mongrel2::Pool.new(config.delete(:uuid), app, config, &after_fork)
    end

    def running?
      if pid
        Process.kill(0, pid.to_i) rescue nil
      end
    end

    def pid
      @pid ||= File.read(instance.send(:pidfile)) rescue nil
    end

    def start
      if running?
        puts "Mongrel2::Pool - Already running with pid #{pid}"
        exit 1
      else
        if instance.daemon?
          fork do
            Process.daemon(true, true)
            logfile = instance.logfile.respond_to?(:write) ? '/dev/null' : instance.logfile
            $stderr.reopen(logfile, 'a+')
            $stdout.reopen(logfile, 'a+')
            instance.send(:run)
            Process.waitall rescue nil
          end
        else
          instance.send(:run)
          Process.waitall rescue nil
        end
        exit 0
      end
    end

    def stop
      if running?
        Process.kill('QUIT', pid.to_i)
      else
        puts "Mongrel2::Pool - Already stopped"
        exit 1
      end
    end

    def restart
      if pid
        Process.kill('HUP', pid.to_i)
      else
        puts "Mongrel2::Pool - Process not running. Starting a new one."
        start
      end
    end

    def kill
      if pid
        Process.kill('TERM', pid.to_i)
        10.times do
          break unless running?
          sleep 0.5
        end

        if running?
          puts "Mongrel2::Pool - Still running, gonna nuke the workers and server."
          kill_workers
          Process.kill('KILL', pid.to_i)
        end
      end
    end

    def more
      raise "Mongrel2::Pool - Not running" unless running?
      Process.kill('TTIN', pid.to_i)
    end

    def less
      raise "Mongrel2::Pool - Not running" unless running?
      Process.kill('TTOU', pid.to_i)
    end

    # TODO this might not be portable across unix flavors.
    def kill_workers
      pids = %x{ps --ppid #{pid}}.split(/\n+/).map {|line| line.sub(%r{^\s*(\d+)\s+.*}, '\\1').to_i}
      pids.shift
      pids.each {|id| Process.kill('KILL', id) rescue nil}
    end
  end # Runner

  def self.runner rackup_file, config_file
    Runner.new(rackup_file, config_file)
  end
end # Mongrel2::Pool
