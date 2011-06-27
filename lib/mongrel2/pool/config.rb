class Mongrel2::Pool
  class Config
    OPTIONS = %w(size listen pidfile logfile uuid isolate daemon after_fork).map(&:to_sym)

    def initialize
      @options = {}
    end

    def method_missing name, *args, &block
      if OPTIONS.include?(name.to_sym)
        @options[name.to_sym] = block ? block : args.shift
      else
        raise ArgumentError, "Invalid option '#{name}'"
      end
    end

    def options
      @options.reject {|key, value| value.nil?}
    end

    def self.parse content
      config = new
      config.instance_eval(content)
      Mongrel2::Pool::DEFAULTS.merge(config.options)
    end

    def self.parse_file file
      raise ArgumentError, "Missing file #{file}" unless File.exists?(file)
      begin
        parse(File.read(file))
      rescue ArgumentError => e
        $stderr.puts $/, "ERROR: Mongrel2::Pool::Config - #{e.message} in file #{file}", $/
        exit 1
      end
    end
  end # Config
end # Mongrel2::Pool
