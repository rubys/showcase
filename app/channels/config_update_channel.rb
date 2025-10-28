class ConfigUpdateChannel < ApplicationCable::Channel
  def subscribed
    stream_from "config_update_#{params[:database]}_#{params[:user_id]}"
  end

  def unsubscribed
  end
end
