class AddKindToSyncRuns < ActiveRecord::Migration[8.1]
  def change
    # "sales" = sincronizacion de ventas (la que ya existia), "purchases" = compras de insumos.
    add_column :sync_runs, :kind, :string, null: false, default: "sales"
    add_index  :sync_runs, [:kind, :created_at]
  end
end
