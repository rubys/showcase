require 'sqlite3'

class HtpasswdUpdater
  def self.update
    return if ENV['RAILS_ENV'] == 'test'
    
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    index_db = "#{dbpath}/index.sqlite3"
    
    # Return early if database doesn't exist
    return unless File.exist?(index_db)
    
    # Query the database directly
    db = SQLite3::Database.new(index_db)
    passwords = db.execute('SELECT password FROM users WHERE password IS NOT NULL ORDER BY password')
    db.close
    
    # Flatten the result and join
    contents = passwords.flatten.compact.join("\n")
    
    # Only write if contents have changed
    htpasswd_file = "#{dbpath}/htpasswd"
    if contents != (IO.read(htpasswd_file) rescue '')
      IO.write(htpasswd_file, contents)
    end
  end
end