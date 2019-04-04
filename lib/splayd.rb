require File.expand_path(File.join(File.dirname(__FILE__), 'config'))

class Splayd
  attr_accessor :row
  attr_reader :id

  @@transaction_mutex = Mutex.new
  @@unseen_timeout = 3600
  @@auto_add = SplayControllerConfig::AutoAddSplayds
  @row = nil # A pointer to the row in the database for this splayd

  def initialize(id)
    @row = $db[:splayds].first(:id => id)
    if not @row
      @row = $db[:splayds].first(:key => id)
    end
    if not @row and @@auto_add
      $db.from(:splayds).insert(:key => id)
      @row = $db[:splayds].first(:key => id)
    end
    if @row then
      @id = @row[:id]
    end
    $log.info("Splayd with ID #{@id} initialized")
  end

  def self.init
    $db.from(:splayds).where(status: ['AVAILABLE', 'PREAVAILABLE']).update(:status => 'UNAVAILABLE')
    Splayd.reset_actions
    Splayd.reset_unseen
  end

  def self.reset_unseen
    # $db.from(:splayds).where("last_contact_time < ? AND ( status = 'AVAILABLE' OR status = 'UNAVAILABLE' OR status = 'PREAVAILABLE')", Time.now.to_i - @@unseen_timeout).each do |splayd|
    $db["SELECT * FROM splayds WHERE
  		last_contact_time<'#{Time.now.to_i - @@unseen_timeout}' AND
  		(status='AVAILABLE' OR
  		status='UNAVAILABLE' OR
  		status='PREAVAILABLE')"].each do |splayd|
      $log.debug("Splayd #{splayd[:id]} (#{splayd[:ip]} - #{splayd[:status]}) not seen " +
        "since #{@@unseen_timeout} seconds (#{splayd[:last_contact_time]}) => RESET")
      # We kill the thread if there is one
      s = Splayd.new(splayd[:id])
      s.kill
      s.reset
    end
  end

  def self.reset_actions
    # When the controller start, if some actions where send but still not
    # replied, we will never receive the reply so we set the action to the
    # FAILURE status.
    $db.from(:actions).where(status: 'SENDING').update(:status => 'FAILURE')
    # [:actions].where(:status=>'SENDING').update(:status=>'FAILURE')
    # Uncomplete actions, jobd should put the again.
    $db[:actions].where(:status => 'TEMP').delete
  end

  def self.gen_session
    return OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s + "session" + rand(1000000).to_s)
  end

  def self.has_job(splayd_id, job_id)
    sj = $db.from(:splayd_jobs).where(splayd_id: splayd_id, job_id: job_id).first
    if sj then return true else return false end
  end

  # Send an action to a splayd only if it is active.
  # For performance reasons, we will not check anymore the availability because
  # 99.9% of time, when an action is sent, the splayd is available. This should
  # have no consequences (other than a little DB space) because when the splayd
  # comes back from a reset state, it will be reset() and the commands deleted.
  def self.add_action(splayd_id, job_id, command, data = '')
    $db.from(:actions).insert(:splayd_id => splayd_id, :job_id => job_id, :command => command, :data => addslashes(data))
    # .do "INSERT INTO actions SET
    #     splayd_id='#{splayd_id}',
    #     job_id='#{job_id}',
    #     command='#{command}',
    #     data='#{addslashes data}'"
    return true
  end

  def self.blacklist
    hosts = []
    $db.from(:blacklist_hosts).each do |row|
      hosts << row[:id]
    end
    return hosts
  end

  def self.localize_all
    return Thread.new do
      $db.from(:splayds).each do |s|
        splayd = Splayd.new(s[:id])
        splayd.localize
      end
    end
  end

  def to_s
    if @row[:name] and @row[:ip]
      return "#{@id} (#{@row[:name]}, #{@row[:ip]})"
    elsif @row[:ip]
      return "#{@id} (#{@row[:ip]})"
    else
      return "#{@id}"
    end
  end

  def check_and_set_preavailable
    r = false
    # to protect the $db object while in use.
    @@transaction_mutex.synchronize do
      $db.transaction do
        status = $db[:splayds].where(id: @id).get(:status).first
        $log.info("STATUS : #{status}")
        if status == 'REGISTERED' or status == 'UNAVAILABLE' or status == 'RESET' then
          $db.from(:splayds).where(id: @id).update(status: 'PREAVAILABLE')
          r = true
        end
      end # COMMIT issued only here
    end
    return r
  end

  # Check that this IP is not used by another splayd.
  def ip_check ip
    query = $db.run("SELECT * FROM splayds WHERE ip='#{ip}' AND `key`!='#{@row.get(:key)}' AND (status='AVAILABLE' OR status='UNAVAILABLE' OR status='PREAVAILABLE')")
    if ip == "127.0.0.1" or ip == "::ffff:127.0.0.1" or not query
      true
    else
      false
    end
  end

  def insert_splayd_infos infos
    infos = JSON.parse infos
    if infos['status']['endianness'] == 0
      infos['status']['endianness'] = "little"
    else
      infos['status']['endianness'] = "big"
    end
    # We don't update ip, key, session and localization informations here
    $db.from(:splayds).where(id: @id).update(
      :name => addslashes(infos['settings']['name']),
      :version => addslashes(infos['status']['version']),
      :lua_version => addslashes(infos['status']['lua_version']),
      :bits => addslashes(infos['status']['bits']),
      :endianness => addslashes(infos['status']['endianness']),
      :os => addslashes(infos['status']['os']),
      :full_os => addslashes(infos['status']['full_os']),
      :architecture => addslashes(infos['status']['architecture']),
      :start_time => addslashes((Time.now.to_f - infos['status']['uptime'].to_f).to_i),
      :max_number => addslashes(infos['settings']['job']['max_number']),
      :max_mem => addslashes(infos['settings']['job']['max_mem']),
      :disk_max_size => addslashes(infos['settings']['job']['disk']['max_size']),
      :disk_max_files => addslashes(infos['settings']['job']['disk']['max_files']),
      :disk_max_file_descriptors => addslashes(infos['settings']['job']['disk']['max_file_descriptors']),
      :network_max_send => addslashes(infos['settings']['job']['network']['max_send']),
      :network_max_receive => addslashes(infos['settings']['job']['network']['max_receive']),
      :network_max_sockets => addslashes(infos['settings']['job']['network']['max_sockets']),
      :network_max_ports => addslashes(infos['settings']['job']['network']['max_ports']),
      :network_send_speed => addslashes(infos['settings']['network']['send_speed']),
      :network_receive_speed => addslashes(infos['settings']['network']['receive_speed'])
    )
    parse_loadavg(infos['status']['loadavg'])
  end

  def update_splayd_infos
    @row = $db[:splayds].first(:id => id)
  end

  def localize
    if @row[:ip] and not @row[:ip] == "127.0.0.1" and not @row[:ip] =~ /192\.168\..*/ and
       not @row[:ip] =~ /10\.0\..*/

      $log.debug("Trying to localize: #{@row[:ip]}")
      begin
        hostname = ""
        begin
          Timeout::timeout(10, StandardError) do hostname = Resolv::getname(@row[:ip]) end
        rescue
          $log.warn("Timeout resolving hostname of IP: #{@row[:ip]}")
        end
        loc = Localization.get(@row[:ip])
        $log.info("#{@id} #{@row[:ip]} #{hostname} " + "#{loc.country_code2.downcase} #{loc.city_name}")
        $db.from(:splayds).where(id: @id).update(
          :hostname => hostname,
          :country => loc.country_code2.downcase,
          :city => loc.city_name,
          :latitude => loc.latitude,
          :longitude => loc.longitude
        )
      rescue => e
        $log.error("Impossible localization of #{@row[:ip]} : #{e}")
      end
    end
  end

  def remove_action action
    $db.from(:actions).where(id: action[:id]).delete
  end

  def update(field, value)
    $db.from(:splayds).where(id: @id).update(field.to_sym => value)
    @row[field.to_sym] = value
  end

  def kill
    $log.info("When kill is called check ID type: #{@id}")
    if SplaydServer.threads[@id]
      SplaydServer.threads.delete(@id).kill
    end
  end

  # DB cleaning when a splayd is reset.
  def reset
    session = Splayd.gen_session

    $db.from(:splayds).where(id: @id).update(:status => 'RESET', :session => session)
    $db.from(:actions).where(splayd_id: @id).delete
    $db.from(:splayd_jobs).where(splayd_id: @id).delete
    $db.from(:splayd_availabilities).insert(:splayd_id => @id, :status => 'RESET', :time => Time.now.to_i)
    # For trace job
    $db.from(:splayd_selections).where(splayd_id: @id).update(:reset => 'TRUE')
  end

  def unavailable
    $db.from(:splayds).where(id: @id).update(:status => 'UNAVAILABLE')
    $db.from(:splayd_availabilities).insert(
      :splayd_id => @id,
      :status => 'UNAVAILABLE',
      :time => Time.now.to_i
    )
    # .do "INSERT INTO splayd_availabilities SET
    #         splayd_id='#{@id[:id]}',
    #         status='UNAVAILABLE',
    #         time='#{Time.now.to_i}'"
  end

  def action_failure
    $db.run("UPDATE actions SET status='FAILURE'
    		WHERE status='SENDING' AND splayd_id='#{@id}'")
  end

  def available
    $db.from(:splayds).where(id: @id).update(:status => 'AVAILABLE')

    $db.from(:splayd_availabilities).insert(
      :splayd_id => @id,
      :ip => @row[:ip],
      :status => 'AVAILABLE',
      :time => Time.now.to_i
    )
    last_contact
    restore_actions
  end

  def last_contact
    t = Time.now.to_i
    $db.from(:splayds).where(id: @id).update(:last_contact_time => t)
    return t
  end

  # Restore actions in failure state.
  def restore_actions
    $db["SELECT * FROM actions WHERE status='FAILURE' AND splayd_id='#{@id}'"].each do |action|
      if action[:command] == 'REGISTER'
        # We should put the FREE-REGISTER at the same place
        # where REGISTER was. But, no other register action concerning
        # this splayd and this job can exists (because registering is
        # split into states), so, if we remove the REGISTER, we can safely
        # add the FREE-REGISTER commands at the top of the
        # actions.
        job = $db.from(:jobs).where(id: action[:job_id]).first
        $db.from(:actions).where(id: action[:id]).delete

        Splayd.add_action(action[:splayd_id], action[:job_id], 'FREE', job[:ref])
        Splayd.add_action(action[:splayd_id], action[:job_id], 'REGISTER', addslashes(job[:code]))
      else
        $db.from(:actions).where(id: action[:id]).update(:status => 'WAITING')
      end
    end
  end

  # Return the next WAITING action and set status to SENDING.
  def next_action
    resu = nil
    $db["SELECT * FROM actions WHERE splayd_id='#{@id}' ORDER BY id"].each do |action|
      $log.info("next action to do: #{action[:id]} - #{action[:command]}")
      if action[:status] == 'TEMP'
        $log.info("INCOMPLETE ACTION: #{action[:command]} " + "(splayd: #{@id}, job: #{action[:job_id]})")
      end
      if action[:status] == 'WAITING'
        $db.from(:actions).where(id: action[:id]).update(:status => 'SENDING')
        resu = action
        break
      end
    end
    return resu
  end

  def s_j_register job_id
    $db.from(:splayd_jobs).where(Sequel.&({ splayd_id: @id }, { job_id: job_id }, { status: "RESERVED" })).update(:status => 'WAITING')
  end

  def s_j_free job_id
    $db.from(:splayd_jobs).where(Sequel.&({ splayd_id: @id }, { job_id: job_id })).delete
  end

  def s_j_start job_id
    $db.from(:splayd_jobs).where(Sequel.&({ splayd_id: @id }, { job_id: job_id })).update(:status => 'RUNNING')
  end

  def s_j_stop job_id
    $db.from(:splayd_jobs).where(Sequel.&({ splayd_id: @id }, { job_id: job_id })).update(:status => 'WAITING')
  end

  def s_j_status data
    data = JSON.parse data
    $db.from(:splayd_jobs).where(splayd_id: @id).exclude(status: 'RESERVED').each do |sj|
      job = $db.from(:jobs).where(id: sj[:job_id]).first
      # There is no difference in Lua between Hash and Array, so when it's
      # empty (an Hash), we encoded it like an empty Array.
      if data['jobs'].class == Hash and data['jobs'][job[:ref]]
        if data['jobs'][job[:ref]]['status'] == "waiting"
          $db.from(:splayd_jobs).where(id: sj[:id]).update(:status => 'WAITING')
        end
        # NOTE normally no needed because already set to RUNNING when
        # we send the START command.
        if data['jobs'][job[:ref]]['status'] == "running"
          $db.from(:splayd_jobs).where(id: sj[:id]).update(:status => 'RUNNING')
        end
      else
        $db.from(:splayd_jobs).where(id: sj[:id]).delete
      end
      # it can't be new jobs in data['jobs'] that don't have already an
      # entry in splayd_jobs
    end
  end

  def parse_loadavg s
    if s.strip != ""
      l = s.split(" ")
      $db.from(:splayds).where(id: @id).update(:load_1 => l[0], :load_5 => l[1], :load_15 => l[2])
    else
      # NOTE should too be fixed in splayd
      $log.warn("Splayd #{@id} report an empty loadavg. ")
      $db.from(:splayds).where(id: @id).update(:load_1 => '10', :load_5 => '10', :load_15 => '10')
    end
  end

  # NOTE then corresponding entry may already have been deleted if the reply
  # comes after the job has finished his registration, but no problem.
  def s_sel_reply(job_id, port, reply_time)
    $db.from(:splayd_selections).where(Sequel.&({ splayd_id: @id }, { job_id: job_id })).update(
      :replied => 'TRUE', :reply_time => reply_time, :port => port
    )
  end
end
