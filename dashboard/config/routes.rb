Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  root "dashboard#index"

  namespace :api do
    resources :clients, only: [ :index ], param: :name do
      member do
        post :start
        post :stop
        post :restart
        get :logs
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
