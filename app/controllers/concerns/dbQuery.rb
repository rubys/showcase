module DbQuery
  def dbquery(db, table, fields=nil, where=nil)
    if fields
      fields = Array(fields).map(&:inspect).join(', ') unless fields.is_a? String
    else
      fields = '*'
    end

    query = "select #{fields} from #{table}"
    query += " where #{where}" if where

    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    csv = `sqlite3 --csv --header #{dbpath}/#{db}.sqlite3 "#{query}"`

    if csv.empty?
      []
    else
      CSV.parse(csv, headers: true).map(&:to_h)
    end
  end
end
