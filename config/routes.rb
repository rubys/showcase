Rails.application.routes.draw do
  root 'event#root'

  resources 'event', only: [:update] do
    get 'settings', on: :collection
  end

  resources :heats do
    post 'redo', on: :collection
  end

  resources :entries

  resources :dances

  resources :people do
    get 'backs', on: :collection
    post 'backs', on: :collection, action: 'assign_backs'
    get 'couples', on: :collection
    get 'students', on: :collection
    get 'entries', on: :member, action: 'get_entries'
    post 'entries', on: :member, action: 'post_entries'
  end

  resources :studios do
    post 'unpair', on: :member
  end
end
