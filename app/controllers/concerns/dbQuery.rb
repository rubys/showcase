module DbQuery
  require 'sqlite3'

  def dbquery(db, table, fields=nil, where=nil)
    dbpath = ENV.fetch('RAILS_DB_VOLUME', 'db')
    dbfile = "#{dbpath}/#{db}.sqlite3"
    dbconn = SQLite3::Database.new(dbfile)
    dbconn.results_as_hash = true

    fields_str = if fields
      Array(fields).map { |f| "`#{f}`" }.join(', ')
    else
      '*'
    end

    query = "SELECT #{fields_str} FROM #{table}"
    query += " WHERE #{where}" if where

    results = dbconn.execute(query)
    results.map { |row| row.transform_keys(&:to_s) }
  end
end
