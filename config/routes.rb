Rails.application.routes.draw do
  root 'event#root'
  get '/instructions', to: 'event#instructions'
  get '/event.xlsx', to: "event#index", as: 'event_spreadsheet'

  resources 'event', only: [:update] do
    get 'publish', on: :collection
    get 'settings', on: :collection
    get 'summary', on: :collection
  end

  resources :heats do
    post 'redo', on: :collection
    get 'book', on: :collection
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
    get 'heats', on: :collection
    get 'entries', on: :member, action: 'get_entries'
    post 'entries', on: :member, action: 'post_entries'
  end

  resources :studios do
    post 'unpair', on: :member
  end

  get '/scores/:judge/heatlist', to: 'scores#heatlist', as: 'judge_heatlist'
  get '/scores/:judge/heat/:heat', to: 'scores#heat', as: 'judge_heat'
  post '/scores/:judge/post', to: 'scores#post', as: 'post_score'
  resources :scores do
    get 'by-level', on: :collection, action: :by_level
    get 'by-age', on: :collection, action: :by_age
    get 'instructor', on: :collection
  end

  resources :solos do
    post 'drop', on: :collection
  end
end
