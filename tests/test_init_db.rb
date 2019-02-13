require "minitest/autorun"

dir = File.dirname(__FILE__)
require "#{dir}/../lib/all"

class TestInitDb < Minitest::Test
  
  def test_verify_db_mysql
    @db = DBUtils::get_new
    self.check_tables(@db)
  end
  
  def check_tables(db)
      assert(@db[:actions])
      assert(@db[:blacklist_hosts])
      assert(@db[:jobs_designated_splayds])
      assert(@db[:jobs_mandatory_splayds])
      assert(@db[:jobs])
      assert(@db[:libs])
      assert(@db[:local_log])
      assert(@db[:locks])
      assert(@db[:splayds_availabilities])
      assert(@db[:splayds_jobs])
      assert(@db[:splayds_libs])
      assert(@db[:splayds_selections])
      assert(@db[:splayds])
  end
  
end