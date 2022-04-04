class CurrentHeatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "current-heat-#{ENV['RAILS_APP_DB']}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
