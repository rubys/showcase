Rails.application.routes.draw do
  root 'event#root'
  get '/instructions', to: 'event#instructions'

  resources 'event', only: [:update] do
    get 'settings', on: :collection
  end

  resources :heats do
    post 'redo', on: :collection
  end

  resources :entries

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
  end
end
