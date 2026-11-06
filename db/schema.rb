# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_06_200446) do
  create_table "daily_sales", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "people", default: 0, null: false
    t.decimal "people_sales", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "synced_at"
    t.integer "tickets", default: 0, null: false
    t.decimal "tips", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_daily_sales_on_date", unique: true
  end

  create_table "ingredient_assignments", force: :cascade do |t|
    t.boolean "automatic", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "fudo_ingredient_id", null: false
    t.integer "ingredient_category_id", null: false
    t.string "ingredient_name"
    t.datetime "updated_at", null: false
    t.index ["fudo_ingredient_id"], name: "index_ingredient_assignments_on_fudo_ingredient_id", unique: true
    t.index ["ingredient_category_id"], name: "index_ingredient_assignments_on_ingredient_category_id"
  end

  create_table "ingredient_categories", force: :cascade do |t|
    t.string "area", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["area", "position"], name: "index_ingredient_categories_on_area_and_position"
    t.index ["name"], name: "index_ingredient_categories_on_name", unique: true
  end

  create_table "ingredient_purchases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "detail"
    t.integer "fudo_expense_id", null: false
    t.integer "fudo_ingredient_id", null: false
    t.integer "fudo_item_id", null: false
    t.string "ingredient_name", null: false
    t.decimal "line_total", precision: 14, scale: 2, null: false
    t.string "provider_name"
    t.date "purchased_on", null: false
    t.decimal "quantity", precision: 14, scale: 4, null: false
    t.datetime "synced_at"
    t.string "unit_name"
    t.decimal "unit_price", precision: 14, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["fudo_ingredient_id", "purchased_on"], name: "idx_on_fudo_ingredient_id_purchased_on_fe9755771d"
    t.index ["fudo_item_id"], name: "index_ingredient_purchases_on_fudo_item_id", unique: true
    t.index ["purchased_on"], name: "index_ingredient_purchases_on_purchased_on"
  end

  create_table "price_alerts", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.decimal "baseline_price", precision: 14, scale: 4, null: false
    t.decimal "change_pct", precision: 8, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "fudo_ingredient_id", null: false
    t.integer "fudo_item_id", null: false
    t.string "ingredient_name", null: false
    t.decimal "new_price", precision: 14, scale: 4, null: false
    t.datetime "notified_at"
    t.decimal "overcost", precision: 14, scale: 2, null: false
    t.string "provider_name"
    t.date "purchased_on", null: false
    t.decimal "quantity", precision: 14, scale: 4, null: false
    t.string "unit_name"
    t.datetime "updated_at", null: false
    t.index ["fudo_ingredient_id", "purchased_on"], name: "index_price_alerts_on_fudo_ingredient_id_and_purchased_on"
    t.index ["fudo_item_id"], name: "index_price_alerts_on_fudo_item_id", unique: true
    t.index ["purchased_on"], name: "index_price_alerts_on_purchased_on"
  end

  create_table "report_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "message"
    t.string "recipients"
    t.date "report_date", null: false
    t.datetime "sent_at"
    t.string "status", default: "sending", null: false
    t.datetime "updated_at", null: false
    t.index ["report_date"], name: "index_report_deliveries_on_report_date"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "days_synced", default: 0, null: false
    t.datetime "finished_at"
    t.date "from_date"
    t.string "kind", default: "sales", null: false
    t.text "message"
    t.integer "sales_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "running", null: false
    t.date "to_date"
    t.datetime "updated_at", null: false
    t.index ["kind", "created_at"], name: "index_sync_runs_on_kind_and_created_at"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "ingredient_assignments", "ingredient_categories"
  add_foreign_key "sessions", "users"
end
