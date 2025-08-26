class OfflinePlaylistChannel < ApplicationCable::Channel
  def subscribed
    stream_from "offline_playlist_#{params[:user_id]}"
  end

  def unsubscribed
  end
end