json.extract! recording, :id, :judge_id, :heat_id, :audio, :created_at, :updated_at
json.url recording_url(recording, format: :json)
json.audio url_for(recording.audio)
