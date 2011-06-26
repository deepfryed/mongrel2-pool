$:.unshift File.dirname(__FILE__) + '/lib'

class MyApp
  def self.call env
    [200, {}, ['hello world', $/]]
  end
end

require 'mongrel2-pool'
Mongrel2::Pool.run('testapp', MyApp, size: 2, isolate: true)
