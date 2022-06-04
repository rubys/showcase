json.extract! user, :id, :userid, :password, :email, :name1, :name2, :token, :link, :sites, :created_at, :updated_at
json.url user_url(user, format: :json)
