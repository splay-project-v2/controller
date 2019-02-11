require './lib/all'
print("Create global lock in DB")
db = DBUtils::get_new
db.run("INSERT INTO locks SET
    id='1',
    job_reservation='0'")
db.disconnect