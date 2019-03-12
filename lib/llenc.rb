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

# NOTE
# why socket.read can return a nil element and do not raise an exception when
# the connection is closed ?
#
# If we don't want a timeout, we set a very big value for timeout but I think
# it would be better to avoid that.

class LLencError < SocketError; end

class LLenc
  def initialize(socket)
    @socket = socket
    @read_timeout = @write_timeout = 24 * 3600
    @ip = @socket.peeraddr[3]
  end

  def set_timeout(time)
    @read_timeout = @write_timeout = time
  end

  def peeraddr
    @socket.peeraddr
  end

  def _log(msg)
    $log.debug "LLenc (#{@ip}): #{msg}" if $log
  end

  def write(datas)
    _log ">>> #{datas}"
    Timeout.timeout(@write_timeout, StandardError) do
      @socket.write(datas.bytesize.to_s + "\n" + datas) if datas
    end
  end

  def read(max = nil)
    Timeout.timeout(@read_timeout, StandardError) do
      length = @socket.readline.to_i
      if max && (length > max)
        raise LLencError, "data too long (#{dl} > #{max})"
      end

      t = @socket.read(length)
      raise LLencError, 'data read error' if t.nil?

      _log "<<< #{t}"
      return t
    end
  end
end
