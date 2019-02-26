## Splay Controller ### v1.3 ###
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
require File.expand_path(File.join(File.dirname(__FILE__), 'db_config'))

class SplayControllerConfig
  CTLVersion = 1.3

  SQL_TYPE = DBConfig::SQL_TYPE
  SQL_DB   = DBConfig::SQL_DB
  SQL_HOST = DBConfig::SQL_HOST
  SQL_USER = DBConfig::SQL_USER
  SQL_PASS = DBConfig::SQL_PASS
  SQL_PORT = DBConfig::SQL_PORT

  SSL = true
  Production = false # Put true in prod, remove some tests to permit local testing.
  AutoAddSplayds = true # In production must be false

  # Permit to detect when a node is comming from a NAT gateway and restore his
  # true IP (from the key in format: "NAT_ip"). Then, nodes from external need
  # to change internal IP by gateway IP and using the same port. That solution
  # need a port mapping between gateway and each internal IPs.
  NATGatewayIP = nil

  LogdIP = nil # nil => controller's ip
  LogMaxSize = 1024 * 1024 * 100 # 100 MB of logs for each nodes.
  LogDir = "#{Dir.pwd}/logs".freeze
  # links/job_key.txt => logs/job_id
  LinkLogDir = "#{Dir.pwd}/links".freeze
  LogdPort = 11_100 # base port (first port if more than one splayd)
  UseSplaydTimestamps = true # use the timestamps on the splayds, adjusted by the controller
  SplaydPort = 11_000 # base port (first port if more than one splayd)

  PublicIP = nil # To set ourself in the blacklist

  NumSplayd = 10
  NumLogd = 10

  # Enable geolocalization from an external module (not installed by default)
  Localize = false

  # SplaydProtocol
  SPSleepTime = 1
  SPPingInterval = 60
  SPSocketTimeout = 60

  LoadavgInterval = 300 # should be 60, but better when async protocol
  StatusInterval = 60
  BlacklistInterval = 120
  UnseenInterval = 60

  # Jobd
  RegisterTimeout = 60
  MaxQueueTimeout = 3600
  JobPollTime = 1
  # Allow native lib/jobs to be submitted
  AllowNativeLibs = false
end
