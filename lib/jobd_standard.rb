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
# When we try to select splayds for a job, the only case that could require a
# synchro is that a splayd can have more new free slots than what we have check
# (because a slot can be freed during the select phase). But that is never a
# problem ! So no locks are needed.

class JobdStandard < Jobd
  @@scheduler = 'standard'

  def self.get_scheduler
    @@scheduler
  end

  # LOCAL => REGISTERING|NO RESSOURCES|QUEUED
  def self.status_local
    @@dlock_jr.get
    c_splayd = nil
    $db[:jobs].where(scheduler: get_scheduler, status: 'LOCAL').each do |job|
      $log.debug('New standard job discovered LOCAL -> REGISTER')
      # Splayds selection
      c_splayd, occupation, nb_selected_splayds, new_job, do_next = status_local_common(job)
      # If this job cannot be submitted immediately, jump to the next one
      next if do_next == true

      q_sel = ''
      q_job = ''
      q_act = ''
      count = 0
      occupation.sort_by { |a| a[1] }
      occupation.each do |splayd_id, _occ|
        q_sel += "('#{splayd_id}','#{job[:id]}'),"
        q_job += "('#{splayd_id}','#{job[:id]}','RESERVED'),"
        q_act += "('#{splayd_id}','#{job[:id]}','REGISTER', 'TEMP'),"

        # We update the cache
        c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
        count += 1
        break if count >= nb_selected_splayds
      end
      $db[:job_mandatory_splayds].where(job_id: job[:id]).each do |mm|
        #  select_all "SELECT * FROM job_mandatory_splayds
        #     WHERE job_id='#{job['id']}'" do |mm|
        splayd_id = mm[:splayd_id]
        q_sel += "('#{splayd_id}','#{job[:id]}'),"
        q_job += "('#{splayd_id}','#{job[:id]}','RESERVED'),"
        q_act += "('#{splayd_id}','#{job[:id]}','REGISTER', 'TEMP'),"
        # We update the cache
        c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
      end
      q_sel = q_sel[0, q_sel.length - 1]
      q_job = q_job[0, q_job.length - 1]
      q_act = q_act[0, q_act.length - 1]
      $db.run("INSERT INTO splayd_selections (splayd_id, job_id) VALUES #{q_sel}")
      $db.run("INSERT INTO splayd_jobs (splayd_id, job_id, status) VALUES #{q_job}")
      $db.run("INSERT INTO actions (splayd_id, job_id, command, status) VALUES #{q_act}")
      $db.run("UPDATE actions SET data='#{addslashes(new_job)}', status='WAITING'
  		  WHERE job_id='#{job[:id]}' AND command='REGISTER' AND status='TEMP'")
      set_job_status(job[:id], 'REGISTERING')
    end
    # $log.info('End of status_local()')
    @@dlock_jr.release
  end

  # REGISTERING => REGISTERING_TIMEOUT|RUNNING
  def self.status_registering
    $db["SELECT * FROM jobs WHERE scheduler='#{get_scheduler}' AND status='REGISTERING'"].each do |job|
      # Mandatory filter
      mandatory_filter = ''
      $db["SELECT * FROM job_mandatory_splayds WHERE job_id='#{job[:id]}'"].each do |mm|
        mandatory_filter += " AND splayd_id!=#{mm[:splayd_id]} "
      end

      # Designated filter
      designated_filter = ''
      pos = 0
      $db["SELECT * FROM job_designated_splayds WHERE job_id='#{job[:id]}'"].each do |jds|
        designated_filter += if pos == 0
                               " AND (splayds.id=#{jds[:splayd_id]}"
                             else
                               " OR splayds.id=#{jds[:splayd_id]}"
                             end
        pos += 1
      end
      designated_filter += ')' if designated_filter != ''

      # NOTE ORDER BY reply_time can not be an excellent idea in that sense that
      # it could advantage splayd near of the controller.
      selected_splayds = []
      $db["SELECT splayd_id FROM splayd_selections WHERE
				  job_id=#{job[:id]} AND
				  replied='TRUE'
				  #{mandatory_filter}
				  ORDER BY reply_time LIMIT #{job[:nb_splayds]}"].each do |m|
        selected_splayds << m[:splayd_id]
      end
      # check if enough splayds have responded
      normal_ok = selected_splayds.size >= job[:nb_splayds]

      mandatory_ok = true

      $db["SELECT * FROM job_mandatory_splayds WHERE job_id='#{job[:id]}'"].each do |mm|
        next if $db["SELECT id FROM splayd_selections WHERE
    					  splayd_id='#{mm[:splayd_id]}' AND
    					  job_id='#{job[:id]}' AND
    					  replied='TRUE'"].first

        mandatory_ok = false
        break
      end

      if normal_ok && mandatory_ok
        selected_splayds.each do |splayd_id|
          $db.run("UPDATE splayd_selections SET
									selected='TRUE'
					WHERE splayd_id='#{splayd_id}' AND job_id='#{job[:id]}'")
        end
        $db["SELECT * FROM job_mandatory_splayds
					  WHERE job_id='#{job[:id]}'"].each do |mm|

          $db.run("UPDATE splayd_selections SET
						  selected='TRUE'
						  WHERE
						  splayd_id='#{mm[:splayd_id]}' AND
						  job_id='#{job[:id]}'")
        end

        # We need to unregister the job on the non selected splayds.
        q_act = ''
        $db["SELECT * FROM splayd_selections WHERE job_id='#{job[:id]}' AND selected='FALSE'"].each do |m_s|
          q_act += "('#{m_s[:splayd_id]}','#{job[:id]}','FREE', '#{job[:ref]}'),"
        end
        if q_act != ''
          q_act = q_act[0, q_act.length - 1]
          $db.run("INSERT INTO actions (splayd_id, job_id, command, data) VALUES #{q_act}")
        end

        send_all_list(job, "SELECT * FROM splayd_selections WHERE job_id='#{job[:id]}' AND selected='TRUE'")

        # We change it before sending the START commands because it
        # seems more consistant... We had problem with first jobs
        # begining to log before the status change was done and refused
        # by the log server.
        set_job_status(job[:id], 'RUNNING')

        # Create a symlink to the log dir
        File.symlink("#{@@log_dir}/#{job[:id]}", "#{@@link_log_dir}/#{job[:ref]}.txt")

        send_start(job, "SELECT * FROM splayd_selections WHERE job_id='#{job[:id]}' AND selected='TRUE'")
      else
        Jobd.status_registering_common(job)
      end
    end
  end

  # RUNNING => ENDED
  def self.status_running
    $db["SELECT * FROM jobs WHERE scheduler='#{get_scheduler}' AND status='RUNNING'"].each do |job|
      unless $db["SELECT * FROM splayd_jobs WHERE job_id='#{job[:id]}' AND status!='RESERVED'"].first
        set_job_status(job[:id], 'ENDED')
      end
    end
  end

  # QUEUED => REGISTERING | QUEUED | NO_RESSOURCES
  def self.status_queued
    @@dlock_jr.get

    c_splayd = nil

    $db["SELECT * FROM jobs WHERE scheduler='#{get_scheduler}' AND
			status='QUEUED' AND (scheduled_at is NULL OR scheduled_at<NOW())"].each do |job|

      # Splayds selection
      c_splayd, occupation, nb_selected_splayds, new_job, do_next = status_queued_common(job)

      # If this job cannot be submitted immediately, jump to the next one
      next if do_next == true

      q_sel = ''
      q_job = ''
      q_act = ''

      count = 0
      occupation.sort_by { |a| a[1] }
      occupation.each do |splayd_id, _occ|
        q_sel += "('#{splayd_id}','#{job[:id]}'),"
        q_job += "('#{splayd_id}','#{job[:id]}','RESERVED'),"
        q_act += "('#{splayd_id}','#{job[:id]}','REGISTER', 'TEMP'),"

        # We update the cache
        c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1

        count += 1
        break if count >= nb_selected_splayds
      end

      $db["SELECT * FROM job_mandatory_splayds WHERE job_id='#{job[:id]}'"].each do |mm|
        splayd_id = mm[:splayd_id]
        q_sel += "('#{splayd_id}','#{job[:id]}'),"
        q_job += "('#{splayd_id}','#{job[:id]}','RESERVED'),"
        q_act += "('#{splayd_id}','#{job[:id]}','REGISTER', 'TEMP'),"

        # We update the cache
        c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
      end

      q_sel = q_sel[0, q_sel.length - 1]
      q_job = q_job[0, q_job.length - 1]
      q_act = q_act[0, q_act.length - 1]
      $db.run("INSERT INTO splayd_selections (splayd_id, job_id) VALUES #{q_sel}")
      $db.run("INSERT INTO splayd_jobs (splayd_id, job_id, status) VALUES #{q_job}")
      $db.run("INSERT INTO actions (splayd_id, job_id, command, status) VALUES #{q_act}")
      $db.run("UPDATE actions SET data='#{addslashes(new_job)}', status='WAITING'
				  WHERE job_id='#{job[:id]}' AND command='REGISTER' AND status='TEMP'")

      set_job_status(job[:id], 'REGISTERING')
    end
    @@dlock_jr.release
  end

  def self.kill_job(job, status_msg = '')
    $log.info("KILLING #{job[:id]}")
    Jobd.status_killed_common(job, status_msg)
  end

  def self.command
    # NOTE splayd_jobs table is cleaned directly by splayd when it apply the
    # free command (or reset)
    $db["SELECT * FROM jobs WHERE scheduler='#{get_scheduler}' AND command IS NOT NULL"].each do |job|
      if job[:command] =~ /kill|KILL/
        kill_job(job, 'user kill')
      else
        msg = "Not understood command: #{job['command']}"
        $db.run("UPDATE jobs SET command_msg='#{msg}' WHERE id='#{job[:id]}'")
      end
      $db.run("UPDATE jobs SET command='' WHERE id='#{job[:id]}'")
    end
  end

  # KILL AT
  def self.kill_max_time
    $db["SELECT * FROM jobs WHERE
			  scheduler='#{get_scheduler}' AND
			  status='RUNNING' AND
			  max_time IS NOT NULL AND
			  status_time + max_time < #{Time.now.to_i}"].each do |job|
      kill_job(job, 'max execution time')
    end
  end
end
