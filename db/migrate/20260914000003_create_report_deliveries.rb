class CreateReportDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :report_deliveries do |t|
      t.date :report_date, null: false
      t.string :recipients
      t.string :status, null: false, default: "sending"
      t.text :message
      t.datetime :sent_at
      t.timestamps
    end
    add_index :report_deliveries, :report_date
  end
end
