size      2
uuid      'testapp'
isolate   true
listen    4000

after_fork do |pid|
  # do any post fork setup here like connecting to db.
end
