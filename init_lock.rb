require File.expand_path(File.join(File.dirname(__FILE__), 'lib/all'))

print('Create global lock in DB')
db = DBUtils.get_new
db.run("INSERT IGNORE INTO locks SET
    id='1',
    job_reservation='0'")
db.disconnect
