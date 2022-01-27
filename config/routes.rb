Rails.application.routes.draw do
  resources :heats
  get 'event/root'
  root 'event#root'
  resources :entries
  resources :dances
  resources :people do
    get 'backs', on: :collection
    get 'couples', on: :collection
    get 'entries', on: :member
    post 'entries', on: :member
  end
  resources :studios
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
