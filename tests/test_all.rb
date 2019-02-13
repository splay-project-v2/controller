require "minitest/autorun" #not required if done at the top of each test class, here to be sure.

dir = File.dirname(__FILE__)
# basic unit tests:
require "#{dir}/test_init_db"
require "#{dir}/test_json_parse"
require "#{dir}/test_splayd"
require "#{dir}/test_utils"

# Splaynet tests:
require "#{dir}/test_topology_parser"
require "#{dir}/test_min_heap"



