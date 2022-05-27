Rails.application.routes.draw do
  resources :add_email_to_events
  # if ENV['RAILS_RELATIVE_URL_ROOT'].present?
  #   mount ActionCable.server => "#{ENV['RAILS_RELATIVE_URL_ROOT']}/cable"
  # end
  mount ActionCable.server => "/showcase/cable"
 
  scope ENV.fetch("RAILS_APP_SCOPE", '') do

    if ENV.fetch("RAILS_APP_DB", '') == 'index'
      root 'event#showcases'

      get "/:year/:city", to: 'event#showcases', year: /\d+/
      get "/:year/:city/", to: 'event#showcases', year: /\d+/
    else
      root 'event#root'
    end

    get '/env', to: 'event#env'
    get '/instructions', to: 'event#instructions'
    get '/event.xlsx', to: "event#index", as: 'event_spreadsheet'
    get '/event.sqlite3', to: "event#database", as: 'event_database'

    scope 'public' do
      get 'heats', to: 'heats#mobile', as: 'public_heats'
    end

    resources 'event', only: [:update] do
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
    end

    resources :heats do
      post 'redo', on: :collection
      get 'book', on: :collection
      get 'mobile', on: :collection
    end

    resources :entries do
      get 'couples', on: :collection
    end

    resources :dances do
      post 'drop', on: :collection
    end

    resources :categories do
      post 'drop', on: :collection
    end

    resources :people do
      get 'backs', on: :collection
      post 'backs', on: :collection, action: 'assign_backs'
      get 'couples', on: :collection
      get 'students', on: :collection
      get 'professionals', on: :collection
      get 'guests', on: :collection
      get 'heats', on: :collection
      get 'heats', on: :member, action: 'individual_heats'
      get 'scores', on: :collection
      get 'scores', on: :member, action: 'individual_scores'
      get 'entries', on: :member, action: 'get_entries'
      post 'entries', on: :member, action: 'post_entries'
      post 'type', on: :collection, action: 'post_type'
      post 'package', on: :collection, action: 'post_package'
      get 'invoice', on: :member
    end

    resources :studios do
      post 'unpair', on: :member
      get 'heats', on: :member
      get 'scores', on: :member
      get 'invoice', on: :member
      get 'invoices', on: :collection
      get 'send-invoice', on: :member
      post 'send-invoice', on: :member
    end

    get '/scores/:judge/heatlist', to: 'scores#heatlist', as: 'judge_heatlist'
    get '/scores/:judge/heat/:heat', to: 'scores#heat', as: 'judge_heat'
    get '/scores/:judge/heat/:heat/:slot', to: 'scores#heat', as: 'judge_heat_slot'
    post '/scores/:judge/post', to: 'scores#post', as: 'post_score'
    resources :scores do
      get 'by-level', on: :collection, action: :by_level
      get 'by-age', on: :collection, action: :by_age
      get 'multis', on: :collection, action: :multis
      get 'instructor', on: :collection
    end

    resources :solos do
      post 'drop', on: :collection
      post 'sort_level', on: :collection
    end

    resources :formations

    resources :multis

    resources :billables do
      post 'drop', on: :collection
    end
  end
end