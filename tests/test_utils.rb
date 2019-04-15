require 'minitest/autorun'
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/utils'))

class TestUtils < Minitest::Test
  def test_addslashes
    assert addslashes(nil) == ''
    assert addslashes(false) == ''
    assert addslashes(' \ ') == ' \\\ '
    assert addslashes(" ' ") == " \\' "
    assert addslashes(' " ') == ' \\" '
  end
end
