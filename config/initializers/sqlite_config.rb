# Monkey patch Rails 7.1 to:
#  * restore Rails 7.0 sqlite3 behavior
#  * retry events when busy

# This should be able to be retired when Rails 8 is releasded.

# WAL mode primarily increases concurrency and write performance, but does
# so in a way that complicates backup and replication, particularly when
# databases are distributed across multiple regions.

# Concurrency is a essentially a non-issue for this application as
# concurrency is largely achieved though having separate databases
# per event.

require 'active_record/connection_adapters/sqlite3_adapter'

module ActiveRecord::ConnectionAdapters
  class SQLite3Adapter < AbstractAdapter
    def configure_connection
      retries = 20
      raw_connection.busy_handler do |count|
        count <= retries
      end

      raw_execute("PRAGMA foreign_keys = ON", "SCHEMA")
      raw_execute("PRAGMA journal_mode = DELETE", "SCHEMA")
      raw_execute("PRAGMA synchronous = FULL", "SCHEMA")
      raw_execute("PRAGMA mmap_size = 0", "SCHEMA")
      raw_execute("PRAGMA cache_size = 2000", "SCHEMA")
    end
  end
end

__END__

What changed in 7.1:

https://www.bigbinary.com/blog/rails-7-1-comes-with-an-optimized-default-sqlite3-adapter-connection-configuration

  - and -

https://github.com/rails/rails/pull/49352

Plans to make it configurable:

https://github.com/rails/rails/pull/50460

Rails 7.1 implementation:

https://github.com/rails/rails/blob/0fb5f67ac413d62df64b8b59094b4fe85999b5c1/activerecord/lib/active_record/connection_adapters/sqlite3_adapter.rb#L748-L786

Rails 7.0 implementation:

https://github.com/rails/rails/blob/7-0-stable/activerecord/lib/active_record/connection_adapters/sqlite3_adapter.rb#L615-L619

---

sqlite3 defaults:

PRAGMA foreign_keys = 0;
PRAGMA journal_mode = delete;
PRAGMA synchronous = 2;
PRAGMA mmap_size = 0;
PRAGMA journal_size_limit = 32768;
PRAGMA cache_size = 2000;
