#!/usr/bin/env ruby

## Splay Controller ### v1.1 ###
## Copyright 2006-2011
## http://www.splay-project.org
##
##
##
## This file is part of Splay.
##
## Splayd is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License,
## or (at your option) any later version.
##
## Splayd is distributed in the hope that it will be useful,but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
## See the GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with Splayd. If not, see <http://www.gnu.org/licenses/>.

# This file will execute all the daemons (including multiple splayds and logds) on
# this computer. Because DBI is not fork safe (if a process halt, the connection
# is closed), we give a different DB connection to every process. We do that too
# because ruby (1.8) threads are not efficient and a splayd (daemon) will have
# dificulties to manage more than 100 threads (=> splayds).
#
# Each 'daemon' can be run standalone. Following the example in this file, you can
# see how easily you would be able to run multiple splayd/jobs on multiple
# computers.

require File.expand_path(File.join(File.dirname(__FILE__), 'lib/common'))
require File.expand_path(File.join(File.dirname(__FILE__), 'lib/all'))

# Redefine the log level (by default ERROR)
$log.level = Logger::DEBUG

puts ">>> Splayd Controller #{SplayControllerConfig::CTLVersion} <<<"
puts
puts 'http://www.splay-project.org'
puts 'Splay Controller is licensed under GPL v3, see COPYING'
puts

# Reset Distributed Locks
$db = DBUtils.get_new
$db.run("UPDATE locks SET job_reservation='0' WHERE id ='1'")
# Init used the $db
Splayd.init
$db.disconnect

(0...SplayControllerConfig::NumLogd).each do |i|
  fork do
    $db = DBUtils.get_new
    LogdServer.new(SplayControllerConfig::LogdPort + i).run.join
  end
end

(0...SplayControllerConfig::NumSplayd).each do |i|
  fork do
    $db = DBUtils.get_new
    SplaydServer.new(SplayControllerConfig::SplaydPort + i).run.join
  end
end

fork do
  $db = DBUtils.get_new
  JobdStandard.run.join
end

fork do
  $db = DBUtils.get_new
  JobdTrace.init
  JobdTrace.run.join
end

fork do
  $db = DBUtils.get_new
  Unseend.run.join
end

fork do
  $db = DBUtils.get_new
  Statusd.run.join
end

fork do
  $db = DBUtils.get_new
  Loadavgd.run.join
end

fork do
  $db = DBUtils.get_new
  Blacklistd.run.join
end

fork do
  $db = DBUtils.get_new
  JobdTraceAlt.run.join
end

# end only on interruption
loop { sleep 1000 }
