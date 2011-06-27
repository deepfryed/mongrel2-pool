size    = 2
uuid    = 'testapp'
isolate = true
daemon  = true
logfile = '/tmp/mongrel2-pool.log'

after_fork do |pid|
  # do any post fork setup here like connecting to db.
end
