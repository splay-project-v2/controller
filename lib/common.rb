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

# Use by local command
require 'logger' # Logger::Error
$log = Logger.new(STDERR)
$log.datetime_format = '%Y-%m-%d %H:%M:%S '
$log.level = Logger::ERROR

require 'socket' # SocketError and SystemCallError (Errno::*)
require 'timeout' # Timeout::Error
require 'openssl' # OpenSSL::OpenSSLError
require 'fileutils'
require 'resolv'
require 'json' # gem install json

dir = File.dirname(__FILE__)

require File.expand_path(File.join(dir, 'db_config'))
require File.expand_path(File.join(dir, 'config'))
require File.expand_path(File.join(dir, 'log_object'))
require File.expand_path(File.join(dir, 'dbutils'))
require File.expand_path(File.join(dir, 'llenc'))
require File.expand_path(File.join(dir, 'utils'))
require File.expand_path(File.join(dir, 'distributed_lock'))

if SplayControllerConfig::Localize
  require File.expand_path(File.join(dir, 'localization'))
end


BasicSocket.do_not_reverse_lookup = true
OpenSSL.debug = false

unless SplayControllerConfig::PublicIP
  $log.warn('You must set your public ip in production mode.')
end
