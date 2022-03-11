class CurrentHeatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "current-heat"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
