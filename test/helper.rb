$:.unshift File.dirname(__FILE__) + '/../lib'

require 'open3'
require 'fileutils'
require 'tempfile'
require 'minitest/unit'
require 'minitest/spec'
require 'mongrel2/pool'

class MiniTest::Unit::TestCase
  def testdir
    @testdir ||= File.absolute_path(File.dirname(__FILE__))
  end

  def config_file
    File.join(testdir, 'mongrel2.conf')
  end

  def db_file
    File.join(testdir, 'config.sqlite')
  end

  def setup
    system("m2sh load --config #{config_file} --db #{db_file}")
  end

  def teardown
    FileUtils.rm_f Dir.glob("#{testdir}/tmp/*")
  end

  def run_app app, size = 1, &block
    stdin, stdout, stderr, thr = Dir.chdir(testdir) do
      Open3.popen3("mongrel2 #{db_file} testapp-server")
    end

    stdin.close
    io  = Tempfile.new('mongrel2-pool-test')
    pid = fork do
      Mongrel2::Pool.run('testapp', app, size: size, logfile: io.path)
    end

    block.call(pid, io)
    ensure
      io.unlink
      Process.kill('TERM', thr.pid) rescue nil
      Process.kill('TERM', pid)     rescue nil
  end
end

MiniTest::Unit.autorun
