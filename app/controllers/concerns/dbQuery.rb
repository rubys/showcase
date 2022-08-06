module DbQuery
  def dbquery(db, table, fields=nil)
    if fields
      fields = Array(fields).map(&:inspect).join(', ')
    else
      fields = '*'
    end

    csv = `sqlite3 --csv --header db/#{db}.sqlite3 "select #{fields} from #{table}"`

    if csv.empty?
      []
    else
      CSV.parse(csv, headers: true).map(&:to_h)
    end
  end
end