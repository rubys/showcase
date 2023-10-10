json.extract! song, :id, :dance_id, :order, :title, :artist, :created_at, :updated_at
json.url song_url(song, format: :json)
