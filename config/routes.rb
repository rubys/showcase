Rails.application.routes.draw do
  root 'event#root'

  resources :heats do
    get 'knobs', on: :collection
    post 'redo', on: :collection
  end

  resources :entries

  resources :dances

  resources :people do
    get 'backs', on: :collection
    get 'couples', on: :collection
    get 'entries', on: :member, action: 'get_entries'
    post 'entries', on: :member, action: 'post_entries'
  end

  resources :studios do
    post 'unpair', on: :member
  end
end
