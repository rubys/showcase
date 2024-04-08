module Retriable
  def retry_transaction(&block)
    f = File.open("tmp/#{ENV.fetch('RAILS_APP_DB', 'db')}-score.lock", File::RDWR|File::CREAT, 0644)
    f.flock File::LOCK_EX
    4.times do
      begin
        return Score.transaction(&block)
      rescue SQLite3::BusyException, ActiveRecord::StatementInvalid, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
        sleep 0.1
      end
    end

    Score.transaction(&block)
  ensure
    f.flock File::LOCK_UN
  end
end