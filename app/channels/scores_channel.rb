class ScoresChannel < ApplicationCable::Channel
  def subscribed
    stream_from "live-scores-#{ENV['RAILS_APP_DB']}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
