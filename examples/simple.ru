$:.unshift File.dirname(__FILE__) + '/../lib'

class MyApp
  def self.call env
    [200, {}, ['hello world', $/]]
  end
end

Mongrel2::Pool.run('testapp', MyApp, size: 2, isolate: true) do |pid|
  # do any post fork setup here like connecting to db.
end
