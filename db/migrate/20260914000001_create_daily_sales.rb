class CreateDailySales < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_sales do |t|
      t.date :date, null: false
      t.decimal :total, precision: 14, scale: 2, null: false, default: 0
      t.integer :tickets, null: false, default: 0
      t.datetime :synced_at
      t.timestamps
    end
    add_index :daily_sales, :date, unique: true
  end
end
