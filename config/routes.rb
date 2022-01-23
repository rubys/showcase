Rails.application.routes.draw do
  root 'event#root'
  resources :entries
  resources :dances
  resources :people
  resources :studios
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
