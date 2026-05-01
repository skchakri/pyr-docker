Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  root "dashboard#index"

  namespace :api do
    resources :clients, only: [ :index ], param: :name do
      member do
        post :start
        post :stop
        post :restart
        post :restart_vite
        get :logs
        get :dev_login
        post :upload_paste
      end
    end

    get    "manager/state"           => "manager#state"
    get    "manager/suggestions"     => "manager#suggestions"
    post   "manager/skills/install"  => "manager#skills_install"
    post   "manager/skills/remove"   => "manager#skills_remove"
    post   "manager/plugins/add"     => "manager#plugins_add"
    post   "manager/plugins/toggle"  => "manager#plugins_toggle"
    post   "manager/plugins/remove"  => "manager#plugins_remove"
    post   "manager/mcp/add"         => "manager#mcp_add"
    post   "manager/mcp/remove"      => "manager#mcp_remove"

    get    "claude/usage"   => "claude#usage"
    get    "claude/history" => "claude#history_index"
    post   "claude/history" => "claude#history_create"
    delete "claude/history" => "claude#history_destroy"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
