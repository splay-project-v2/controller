require File.expand_path(File.join(File.dirname(__FILE__), 'splayd'))

class SplaydProtocol
  class RegisterError < StandardError; end
  class ProtocolError < StandardError; end

  @@sleep_time = SplayControllerConfig::SPSleepTime
  @@ping_interval = SplayControllerConfig::SPPingInterval
  @@socket_timeout = SplayControllerConfig::SPSocketTimeout
  @@logd_ip = SplayControllerConfig::LogdIP
  @@logd_port = SplayControllerConfig::LogdPort
  @@log_max_size = SplayControllerConfig::LogMaxSize
  @@num_logd = SplayControllerConfig::NumLogd
  @@localize = SplayControllerConfig::Localize
  @@nat_gateway_ip = SplayControllerConfig::NATGatewayIP

  @splayd = nil
  @ip = nil
  @so_ori = nil
  @so = nil
  @id = nil

  def initialize(so)
    @ip = so.peeraddr[3]
    @so_ori = so
    @so = LLenc.new(so)
    @so.set_timeout(@@socket_timeout)
   end

  def run
    Thread.new do
      begin
        auth
        main
      rescue Sequel::Error => e
        $log.info(e.backtrace)
        $log.fatal(e.class.to_s + ': ' + e.to_s + "\n" + e.backtrace.join("\n"))
      rescue StandardError => e
        # "normal" situation
        $log.info(e.backtrace)
        $log.warn(e.class.to_s + ': ' + e.to_s)
      ensure
        # When the thread is killed, this part is NOT threaded !
        if @splayd && @row && @row[:key]
          $log.info("Thread of splayd (#{@row[:key]}) will end now.")
        else
          $log.info("Thread of splayd (ip: #{@ip}) will end now.")
        end

        SplaydServer.threads.delete(@id) if @splayd
        begin; @so_ori.close; rescue StandardError; end
      end
    end
  end

  def refused(msg)
    @so.write 'REFUSED'
    @so.write msg
    raise RegisterError, msg
  end

  # Initialize splayd connection, authenticate, session, ...
  def auth
    raise ProtocolError, 'KEY' if @so.read != 'KEY'

    key = addslashes(@so.read)
    session = addslashes(@so.read)

    @splayd = Splayd.new(key)
    $log.info("New splayd created, its ID:  #{@splayd.row[:id]} - key #{key}")
    if !@splayd.row[:id] || (@splayd.row[:status] == 'DELETED')
      refused "That splayd doesn't exist or was deleted: #{key}"
    end
    if @@nat_gateway_ip && (@ip == @@nat_gateway_ip)
      if key =~ /NAT_([^_]*)_.*/ || key =~ /NAT_(.*)/
        $log.info("#{@splayd}: IP change (NAT) from #{@ip} to #{Regexp.last_match(1)}")
        @ip = Regexp.last_match(1)
      else
        $log.info("#{@splayd[:id]}: IP of NAT gateway without replacement.")
      end
    end
    # if not @splayd.check_and_set_preavailable
    #  refused "Your splayd is already connected. " +
    #     "Try to kill an existing process or wait " +
    #     "2 minutes and retry."
    # end
    # From here if there is not an external error (socket or db problem), the
    # splayd will be accepted.

    old_ip = @splayd.row[:ip]
    begin
      SplaydServer.threads[@id] = Thread.current

      # update ip if needed
      @splayd.update('ip', @ip) if @ip != old_ip

      # check if we can restore the session or not
      if (session != @splayd.row[:session]) || (@ip != old_ip)
        same = false
        @splayd.reset # (change session too)
      else
        same = true
      end

      @so.write 'OK'
      if @splayd.row[:session]
        @so.write @splayd.row[:session]
      else
        @so.write 'NULL'
      end

      if same
        $log.info("#{@splayd}: Session OK")
      else
        @so.write 'INFOS'
        @so.write @ip
        raise ProtocolError, 'INFOS not OK' if @so.read != 'OK'

        infos = @so.read # no addslashes (json)

        @splayd.insert_splayd_infos(infos)
        @splayd.update_splayd_infos

        bl = Splayd.blacklist
        @so.write 'BLACKLIST'
        @so.write bl.to_json
        raise ProtocolError, 'BLACKLIST not OK' if @so.read != 'OK'

        logv = {}
        logv['ip'] = @@logd_ip
        logv['port'] = @@logd_port + rand(@@num_logd)
        logv['max_size'] = @@log_max_size
        @so.write 'LOG'
        @so.write logv.to_json
        raise ProtocolError, 'LOG not OK' if @so.read != 'OK'

        $log.info("#{@splayd}: Log port: #{logv['port']}")
      end
      $log.info("#{@splayd}: Auth OK")
      @splayd.available
    rescue StandardError => e
      # restore previous status (REGISTER, UNAVAILABLE or RESET)
      @splayd.update('status', @splayd.row[:status])
      raise e
    end

    if (@ip != old_ip) && @@localize
      $log.info("#{@splayd}: Localization")
      @splayd.localize
    end

    # TODO: Invariant check @splayd.row must be == to a new fetch of infos
  end

  def main
    last_contact = @splayd.last_contact
    running = true
    while running
      action = @splayd.next_action

      if !action
        if Time.now.to_i - last_contact > @@ping_interval
          # "Inlining PING" Avoid 2 DB operations
          @so.write 'PING'
          raise ProtocolError, 'PING not OK' if @so.read != 'OK'

          last_contact = @splayd.last_contact
        end
        sleep(rand(@@sleep_time * 2 * 100).to_f / 100)
      else
        $log.info("#{@splayd}: Action: #{action[:command]}")
        start_time = Time.now.to_f
        @so.write action[:command]
        if action[:data]
          if (action[:command] == 'LIST') && action[:position]
            action[:data] = action[:data].sub(/_POSITION_/, action[:position].to_s)
          end
          @so.write action[:data]
        end
        reply_code = @so.read
        $log.info("Answer #{reply_code}")
        if reply_code == 'OK'
          if action[:command] == 'REGISTER'
            port = addslashes(@so.read)
            reply_data = port
          end
          if action[:command] == 'STATUS'
            reply_data = @so.read # no addslashes (json)
          end
          reply_data = addslashes(@so.read) if action[:command] == 'LOADAVG'
          if (action[:command] == 'HALT') || (action[:command] == 'KILL')
            running = false
          end
        end
        reply_time = Time.now.to_f - start_time

        # We tolerate some errors because one command
        # can be sent twice if there is a controller failure
        # juste after the send. But REGISTER can not have an
        # error because we don't re-send it, we send an
        # FREE then REGISTER again to avoid that.

        # All the @db.s_j_* functions are replayable.

        if action[:command] == 'REGISTER'
          if reply_code == 'OK'
            # Update the job slot from RESERVED to WAITING
            @splayd.s_j_register(action[:job_id])
            @splayd.s_sel_reply(action[:job_id], reply_data, reply_time)
          else
            raise ProtocolError, "REGISTER not OK: #{reply_code}"
          end
        end

        if action[:command] == 'START'
          if (reply_code == 'OK') || (reply_code == 'RUNNING')
            @splayd.s_j_start(action[:job_id])
          else
            raise ProtocolError, "START not OK: #{reply_code}"
          end
        end

        if action[:command] == 'STOP'
          if (reply_code == 'OK') || (reply_code == 'NOT_RUNNING')
            @splayd.s_j_stop(action[:job_id])
          else
            raise ProtocolError, "STOP not OK: #{reply_code}"
          end
        end

        @splayd.s_j_free(action[:job_id]) if action[:command] == 'FREE'

        @splayd.s_j_status(reply_data) if action[:command] == 'STATUS'

        @splayd.parse_loadavg(reply_data) if action[:command] == 'LOADAVG'

        # We will remove the action here so, if the
        # controller crash between the reply and here, we
        # will do (or redo) the proper DB things.
        @splayd.remove_action(action)

        last_contact = @splayd.last_contact
      end
    end
  ensure
    @splayd.unavailable
    @splayd.action_failure
  end
end
