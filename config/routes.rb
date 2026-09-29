Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
  resources :datasets, except: :destroy do
    resources :source_files, only: %i[create show] do
      resource :field_mapping, only: %i[edit update], controller: "field_mappings"
    end
  end
end
