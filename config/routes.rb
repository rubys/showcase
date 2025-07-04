Rails.application.routes.draw do
  unless ENV['FLY_REGION']
    mount ActionCable.server => "/showcase/cable"
  end

  get "/up", to: proc { [200, {}, ["ok"]] }, as: :rails_health_check

  scope ENV.fetch("RAILS_APP_SCOPE", '') do
    get "/docs/", to: "docs#page", trailing_slash: true, defaults: {page: 'index'}
    get "/docs/*page", to: "docs#page"

    if ENV.fetch("RAILS_APP_DB", '') == 'index'
      root 'event#showcases'

      get "/:year/:city", to: 'event#showcases', year: /\d+/
      get "/:year/:city/", to: 'event#showcases', year: /\d+/

      get "/:year", to: 'event#showcases', year: /\d+/
      get "/:year/", to: 'event#showcases', year: /\d+/, as: 'year',
        trailing_slash: true

      get "/regions/:region", to: 'event#showcases', as: 'region'
      get "/studios/", to: "event#regions", trailing_slash: true
      get "/events/", to: "event#showcases", trailing_slash: true
      get "/studios/:studio", to: 'event#showcases', as: 'studio_events'

      get "logs", to: 'event#logs'
    else
      root 'event#root'
    end

    if ENV.fetch("RAILS_APP_DB", '') == 'index' or Rails.env.test?
      get "/inventory", to: 'event#inventory'
      match "/upload" => "event#upload", via: [:get, :post]

      get 'admin/', to: "admin#index"
      get 'admin/regions', to: 'admin#regions',  trailing_slash: true
      post 'admin/regions', to: 'admin#create_region',  trailing_slash: true
      get 'admin/regions/:code', to: 'admin#show_region', as: 'show_region'
      delete 'admin/regions/:code', to: 'admin#destroy_region', as: 'destroy_region'
      get 'admin/new-region', to: 'admin#new_region'
      get 'admin/apply', to: 'admin#apply'
    end

    get '/env', to: 'event#env'
    get '/console', to: 'event#console' if Rails.env.development?
    match '/select', to: 'event#select', via: %i(get post)
    get '/auth', to: 'event#auth'
    get '/instructions', to: 'event#instructions'
    get '/landing', to: 'event#landing'
    get '/event.xlsx', to: "event#spreadsheet", as: 'event_spreadsheet'
    get '/event.json', to: "event#spreadsheet", as: 'event_json'
    get '/judge.xlsx', to: "event#judge", as: 'judge_spreadsheet'
    get '/judge.json', to: "event#judge", as: 'judge_json'
    get '/event.sqlite3', to: "event#database", as: 'event_database'
    get '/regions/', to: "event#regions", trailing_slash: true
    get '/regions/:region/status', to: "event#region", as: 'region_status'
    get '/regions/:region/songs', to: "event#songs", as: 'region_songs'
    get '/regions/:region/logs/:file', to: "event#region_log", as: "region_log",
      constraints: { file: /[-\w.]+/ }

    scope 'public' do
      get 'heats', to: 'heats#mobile', as: 'public_heats'
      get 'counter', to: 'event#counter', as: 'public_counter'
      get 'recordings/student/:token', to: 'recordings#student', as: 'student_recordings'
    end

    resources 'event', only: [:update] do
      get 'counter', on: :collection
      get 'publish', on: :collection
      get 'settings', on: :collection
      get 'summary', on: :collection
      post 'start_heat', on: :collection
      get 'ages', on: :collection
      post 'ages', on: :collection
      get 'levels', on: :collection
      post 'levels', on: :collection
      get 'dances', on: :collection
      post 'dances', on: :collection
      get 'clone', on: :collection
      post 'clone', on: :collection
      get 'qrcode', on: :collection
      match 'import', on: :collection, via: %i(get post)
    end

    resources :heats do
      post 'redo', on: :collection
      post 'undo', on: :collection
      post 'renumber', on: :collection
      post 'schedule', on: :collection, to: 'heats#schedule_unscheduled'
      post 'drop', on: :collection
      get 'book', on: :collection
      get 'mobile', on: :collection
      get 'djlist', on: :collection
      post 'reset_open', on: :collection
      post 'reset_closed', on: :collection
    end

    resources :entries do
      get 'couples', on: :collection
      post 'reset_ages', on: :collection
    end

    get '/dances/:dance/songs', to: 'songs#dancelist', as: 'dance_songlist'
    post '/dances/:dance/upload-songs', to: 'songs#upload', as: 'dance_song_upload'
    resources :dances do
      post 'drop', on: :collection
      get 'form', on: :collection
      post 'form-update', on: :collection, as: 'update_form'
      post 'agenda', on: :collection
    end

    resources :categories do
      post 'redo', on: :collection
      post 'drop', on: :collection
      post 'toggle_lock', on: :collection
      post 'toggle_lock', on: :member
    end

    match "/people/certificates", to: 'people#certificates', via: %i(get post)
    get "/people/package/:package_id", to: "people#package", as: 'people_package'
    resources :people do
      get 'backs', on: :collection
      post 'backs', on: :collection, action: 'assign_backs'
      get 'couples', on: :collection
      get 'students', on: :collection
      get 'professionals', on: :collection
      get 'labels', on: :collection
      get 'back-numbers', on: :collection, action: 'back_numbers'
      get 'guests', on: :collection
      get 'heats', on: :collection
      get 'heats', on: :member, action: 'individual_heats'
      get 'scores', on: :collection
      get 'scores', on: :member, action: 'individual_scores'
      get 'entries', on: :member, action: 'get_entries'
      post 'entries', on: :member, action: 'post_entries'
      post 'type', on: :collection, action: 'post_type'
      post 'package', on: :collection, action: 'post_package'
      post 'studio_list', on: :collection, action: 'studio_list'
      get 'invoice', on: :member
      get 'instructor_invoice', on: :member
      get 'staff', on: :collection
      post 'toggle_present', on: :member
      post 'ballroom', on: :member
      post 'review_solos', on: :member
      post 'assign_judges', on: :member
      post 'reset_assignments', on: :member
      post 'remove_option', on: :member
      post 'show_assignments', on: :member
    end

    resources :studios do
      post 'unpair', on: :member
      get 'heats', on: :member
      get 'scores', on: :member
      get 'invoice', on: :member
      get 'student-invoices', on: :member
      get 'invoices', on: :collection
      get 'labels', on: :collection
      get 'send-invoice', on: :member
      post 'send-invoice', on: :member
      get 'solos', on: :member
    end

    resources :tables do
      get 'arrange', on: :collection
      post 'update-positions', on: :collection, as: 'update_positions'
      post 'assign', on: :collection
      patch 'renumber', on: :collection
      get 'studio/:id', on: :collection, action: :studio, as: 'studio'
    end

    get '/scores/:judge/heatlist', to: 'scores#heatlist', as: 'judge_heatlist'
    get '/scores/:judge/heat/:heat', to: 'scores#heat', as: 'judge_heat', heat: /\d+\.?\d*/
    get '/scores/:judge/heat/:heat/:slot', to: 'scores#heat', as: 'judge_heat_slot', heat: /\d+\.?\d*/
    post '/scores/:judge/post', to: 'scores#post', as: 'post_score'
    post '/scores/:judge/sort', to: 'scores#sort', as: 'sort_scores'
    post '/scores/:judge/post-feedback', to: 'scores#post_feedback', as: 'post_feedback'
    resources :scores do
      match 'by-studio', on: :collection, action: :by_studio, via: %i(get post)
      match 'by-level', on: :collection, action: :by_level, via: %i(get post)
      match 'by-age', on: :collection, action: :by_age, via: %i(get post)
      match 'multis', on: :collection, action: :multis, via: %i(get post)
      match 'pros', on: :collection, action: :pros, via: %i(get post)
      match 'instructor', on: :collection, via: %i(get post)
      post 'reset', on: :collection
      get 'comments', on: :collection

      match 'details/by-level', on: :collection, action: :by_level, via: %i(get post), defaults: {details: true}
      match 'details/by-age', on: :collection, action: :by_age, via: %i(get post), defaults: {details: true}
      match 'details/multis', on: :collection, action: :multis, via: %i(get post), defaults: {details: true}
    end

    resources :solos do
      get 'djlist', on: :collection
      post 'drop', on: :collection
      post 'sort_level', on: :collection
      post 'sort_gap', on: :collection
      get 'critiques0', on: :collection
      get 'critiques1', on: :collection
      get 'critiques2', on: :collection
    end

    resources :songs do
      post 'drop', on: :collection
    end

    resources :formations

    resources :multis

    resources :billables do
      post 'drop', on: :collection
      match 'people', on: :member, via: %i(get post)
      get 'missing', on: :member

      post 'add-age-costs', on: :collection
      post 'update-age-costs', on: :collection
    end

    match "/password/reset", to: 'users#password_reset', via: %i(get post)
    match "/password/verify", to: 'users#password_verify', via: %i[get patch]

    resources :users do
      get 'auth', on: :member
    end

    resources :showcases do
      post 'drop', on: :collection
    end

    post '/locations/users', to: 'users#update_location', as: 'locations_users'
    resources :locations do
      get 'first-event', on: :collection
      get 'events', on: :member
      get 'auth', on: :member
      get 'sisters', on: :member
      post 'update_sisters', on: :member
      get 'locale', on: :collection
    end

    resources :feedbacks do
      post 'update_values', on: :collection
      post 'update_abbrs', on: :collection
      post 'drop', on: :collection
      post 'reset', on: :collection
    end

    get '/recordings/:judge/heat/:heat', to: 'recordings#heat', as: 'recording_heat', heat: /\d+\.?\d*/
    get '/recordings/:judge/heat/:heat/:slot', to: 'recordings#heat', as: 'recording_heat_slot', heat: /\d+\.?\d*/
    post '/recordings/:judge_id/heat/:heat_id/upload', to: 'recordings#upload', as: 'upload_recording'
    resources :recordings do
    end
  end

  post '/showcase/events/console', to: 'event#console'
  post '/events/console', to: 'event#console'
end
