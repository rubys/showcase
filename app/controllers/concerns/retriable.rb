module Retriable
  def retry_transaction(model_class = Score, &block)
    f = File.open("tmp/#{ENV.fetch('RAILS_APP_DB', 'db')}-score.lock", File::RDWR|File::CREAT, 0644)
    f.flock File::LOCK_EX
    4.times do
      begin
        return model_class.transaction(&block)
      rescue SQLite3::BusyException, ActiveRecord::StatementInvalid, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
        sleep 0.1
      end
    end

    model_class.transaction(&block)
  ensure
    f.flock File::LOCK_UN
  end

  # Simpler retry wrapper for operations that don't need explicit transactions
  def retry_on_lock(retries: 4, &block)
    f = File.open("tmp/#{ENV.fetch('RAILS_APP_DB', 'db')}-score.lock", File::RDWR|File::CREAT, 0644)
    f.flock File::LOCK_EX
    retries.times do
      begin
        return block.call
      rescue SQLite3::BusyException, ActiveRecord::StatementInvalid, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::StatementTimeout
        sleep 0.1
      end
    end

    block.call
  ensure
    f.flock File::LOCK_UN
  end
end