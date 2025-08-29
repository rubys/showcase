module DbQuery
  require 'sqlite3'

  def dbquery(db, table, fields=nil, where=nil)
    dbpath = ENV.fetch('RAILS_DB_VOLUME', 'db')
    dbfile = "#{dbpath}/#{db}.sqlite3"
    
    # Return empty results if database doesn't exist
    return [] unless File.exist?(dbfile)
    
    dbconn = SQLite3::Database.new(dbfile)
    dbconn.results_as_hash = true

    fields_str = if fields
      Array(fields).map { |f| "\"#{f}\"" }.join(', ')
    else
      '*'
    end

    query = "SELECT #{fields_str} FROM \"#{table}\""
    query += " WHERE #{where}" if where

    results = dbconn.execute(query)
    results.map { |row| row.transform_keys(&:to_s) }
  rescue SQLite3::SQLException
    []
  ensure
    dbconn&.close
  end

  def dbquery_raw(db, sql)
    dbpath = ENV.fetch('RAILS_DB_VOLUME', 'db')
    dbfile = "#{dbpath}/#{db}.sqlite3"
    
    # Return empty results if database doesn't exist
    return [] unless File.exist?(dbfile)
    
    dbconn = SQLite3::Database.new(dbfile)
    dbconn.results_as_hash = true

    results = dbconn.execute(sql)
    results.map { |row| row.transform_keys(&:to_s) }
  rescue SQLite3::SQLException
    []
  ensure
    dbconn&.close
  end
end
