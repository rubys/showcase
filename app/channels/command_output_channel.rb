class CommandOutputChannel < ApplicationCable::Channel
  def subscribed
    database = params[:database]
    user_id = params[:user_id]
    job_id = params[:job_id]

    # Stream name follows pattern: command_output_{database}_{user_id}_{job_id}
    stream_from "command_output_#{database}_#{user_id}_#{job_id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
