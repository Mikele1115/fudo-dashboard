Rails.application.routes.draw do
  resource :session                      # login / logout
  resources :passwords, param: :token    # recuperar contrasena
  root "dashboard#show"

  get  "historial", to: "history#index", as: :history
  get  "insumos", to: "ingredients#index", as: :ingredients
  get  "insumos/:id", to: "ingredients#show", as: :ingredient, constraints: { id: /\d+/ }
  post "insumos/actualizar", to: "ingredients#sync", as: :sync_ingredients
  post "sincronizar", to: "syncs#create", as: :sync
  get  "informe/:date", to: "reports#show", as: :report, constraints: { date: /\d{4}-\d{2}-\d{2}/ }
  post "informe", to: "reports#create", as: :reports

  get "up" => "rails/health#show", as: :rails_health_check
end
