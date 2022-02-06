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

ActiveRecord::Schema.define(version: 2022_02_06_193854) do

  create_table "ages", force: :cascade do |t|
    t.string "category"
    t.string "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

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

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.string "location"
    t.string "date"
    t.integer "heat_range_cat"
    t.integer "heat_range_level"
    t.integer "heat_range_age"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "heats", force: :cascade do |t|
    t.integer "number"
    t.integer "entry_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["entry_id"], name: "index_heats_on_entry_id"
  end

  create_table "levels", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "people", force: :cascade do |t|
    t.string "name"
    t.integer "studio_id"
    t.string "type"
    t.integer "back"
    t.string "level"
    t.integer "age_id"
    t.string "role"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["age_id"], name: "index_people_on_age_id"
    t.index ["studio_id"], name: "index_people_on_studio_id"
  end

  create_table "studio_pairs", force: :cascade do |t|
    t.integer "studio1_id", null: false
    t.integer "studio2_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["studio1_id"], name: "index_studio_pairs_on_studio1_id"
    t.index ["studio2_id"], name: "index_studio_pairs_on_studio2_id"
  end

  create_table "studios", force: :cascade do |t|
    t.string "name"
    t.integer "tables"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  add_foreign_key "entries", "dances"
  add_foreign_key "entries", "people", column: "follow_id"
  add_foreign_key "entries", "people", column: "lead_id"
  add_foreign_key "heats", "entries"
  add_foreign_key "people", "ages"
  add_foreign_key "people", "studios"
  add_foreign_key "studio_pairs", "studios", column: "studio1_id"
  add_foreign_key "studio_pairs", "studios", column: "studio2_id"
end
