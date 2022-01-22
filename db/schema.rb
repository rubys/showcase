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

ActiveRecord::Schema.define(version: 2022_01_22_173243) do

  create_table "dances", force: :cascade do |t|
    t.string "name"
    t.string "category"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "entries", force: :cascade do |t|
    t.integer "count"
    t.string "category"
    t.integer "dance_id", null: false
    t.integer "lead_id", null: false
    t.integer "follow_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["dance_id"], name: "index_entries_on_dance_id"
    t.index ["follow_id"], name: "index_entries_on_follow_id"
    t.index ["lead_id"], name: "index_entries_on_lead_id"
  end

  create_table "people", force: :cascade do |t|
    t.string "name"
    t.integer "studio_id", null: false
    t.string "type"
    t.integer "back"
    t.string "level"
    t.string "category"
    t.string "role"
    t.boolean "friday_dinner"
    t.boolean "saturday_lunch"
    t.boolean "saturday_dinner"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["studio_id"], name: "index_people_on_studio_id"
  end

  create_table "studios", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  add_foreign_key "entries", "dances"
  add_foreign_key "entries", "people", column: "follow_id"
  add_foreign_key "entries", "people", column: "lead_id"
  add_foreign_key "people", "studios"
end
