Rails.application.routes.draw do
  resource :session                      # login / logout
  resources :passwords, param: :token    # recuperar contrasena
  root "dashboard#show"

  get  "historial", to: "history#index", as: :history
  get  "insumos", to: "ingredients#index", as: :ingredients
  get   "insumos/categorias", to: "ingredient_categories#index", as: :ingredient_categories
  patch "insumos/categorias", to: "ingredient_categories#update"
  post  "insumos/categorias/nueva", to: "ingredient_categories#create", as: :create_ingredient_category
  post  "insumos/categorias/reclasificar", to: "ingredient_categories#reclassify", as: :reclassify_ingredient_categories
  get   "insumos/categorias/:id", to: "ingredient_categories#show", as: :ingredient_category, constraints: { id: /[0-9]+/ }
  get  "insumos/:id", to: "ingredients#show", as: :ingredient, constraints: { id: /[0-9]+/ }
  post "insumos/actualizar", to: "ingredients#sync", as: :sync_ingredients
  post "alertas/:id/vista", to: "price_alerts#acknowledge", as: :acknowledge_alert, constraints: { id: /[0-9]+/ }
  post "sincronizar", to: "syncs#create", as: :sync
  get  "informe/:date", to: "reports#show", as: :report, constraints: { date: /\d{4}-\d{2}-\d{2}/ }
  post "informe", to: "reports#create", as: :reports

  get "up" => "rails/health#show", as: :rails_health_check
end
