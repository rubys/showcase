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
    get 'entries', on: :member
    post 'entries', on: :member
  end

  resources :studios do
    post 'unpair', on: :member
  end
end
