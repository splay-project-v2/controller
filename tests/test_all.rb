require 'minitest/autorun' # not required if done at the top of each test class, here to be sure.

dir = File.dirname(__FILE__)
require File.expand_path(File.join(dir, '../lib/all'))

require File.expand_path(File.join(dir, '../lib/common'))

$log.level = Logger::ERROR

# basic unit tests:
require File.expand_path(File.join(dir, 'test_init_db'))
require File.expand_path(File.join(dir, 'test_json_parse'))
require File.expand_path(File.join(dir, 'test_splayd'))
require File.expand_path(File.join(dir, 'test_utils'))

# Splaynet tests:
require File.expand_path(File.join(dir, 'test_topology_parser'))
require File.expand_path(File.join(dir, 'test_min_heap'))
