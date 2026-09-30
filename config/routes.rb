Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
  resources :datasets, except: :destroy do
    resources :imported_records, only: %i[index show], controller: "imported_records"
    resources :source_files, only: %i[create show] do
      resource :field_mapping, only: %i[edit update], controller: "field_mappings"
      resource :import_preview, only: :show, controller: "import_previews"
      resource :import, only: :create, controller: "imports"
      resources :import_runs, only: :show, controller: "import_runs"
    end
  end
end
