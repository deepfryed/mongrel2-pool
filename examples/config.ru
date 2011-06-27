$:.unshift File.dirname(__FILE__) + '/../lib'

class MyApp
  def self.call env
    [200, {}, ['hello world', $/]]
  end
end

run MyApp
