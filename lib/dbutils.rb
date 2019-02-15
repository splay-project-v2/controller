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

require 'sequel'

class DBUtils
  # Return new connection to the DB
  def self.get_new
    $log.info('New DB connection (Sequel+MySQL)') if $log
    url = "mysql2://#{SplayControllerConfig::SQL_USER}:#{SplayControllerConfig::SQL_PASS}@" \
            "#{SplayControllerConfig::SQL_HOST}:#{SplayControllerConfig::SQL_PORT}/#{SplayControllerConfig::SQL_DB}"
    db = Sequel.connect(url)

    # Allow smooth transition from previous DBI driver, aliasing the DBI's [do] with Sequel's [run]
    class << db
      alias_method :do, :run
    end

    db
  end

  def self.get_new_mysql_sequel
    get_new
  end
end
