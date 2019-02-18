require 'minitest/autorun'

require File.expand_path(File.join(File.dirname(__FILE__), '../lib/all'))

class TestInitDb < Minitest::Test
  def test_verify_db_mysql
    @db = DBUtils.get_new
    check_tables(@db)
  end

  def check_tables(_db)
    assert(@db[:actions])
    assert(@db[:blacklist_hosts])
    assert(@db[:jobs_designated_splayds])
    assert(@db[:jobs_mandatory_splayds])
    assert(@db[:jobs])
    assert(@db[:local_log])
    assert(@db[:locks])
    assert(@db[:splayds_availabilities])
    assert(@db[:splayds_jobs])
    assert(@db[:splayds_selections])
    assert(@db[:splayds])
  end
end
