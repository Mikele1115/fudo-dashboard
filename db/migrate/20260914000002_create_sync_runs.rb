class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string :status, null: false, default: "running"
      t.datetime :started_at
      t.datetime :finished_at
      t.date :from_date
      t.date :to_date
      t.integer :days_synced, null: false, default: 0
      t.integer :sales_count, null: false, default: 0
      t.text :message
      t.timestamps
    end
  end
end
