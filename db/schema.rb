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

ActiveRecord::Schema[7.0].define(version: 2022_04_25_210448) do
  create_table "ages", force: :cascade do |t|
    t.string "category"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.integer "order"
    t.string "day"
    t.string "time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dances", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "open_category_id"
    t.integer "closed_category_id"
    t.integer "order"
    t.integer "solo_category_id"
    t.index ["closed_category_id"], name: "index_dances_on_closed_category_id"
    t.index ["open_category_id"], name: "index_dances_on_open_category_id"
    t.index ["solo_category_id"], name: "index_dances_on_solo_category_id"
  end

  create_table "entries", force: :cascade do |t|
    t.integer "age_id", null: false
    t.integer "level_id", null: false
    t.integer "lead_id", null: false
    t.integer "follow_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "instructor_id"
    t.index ["age_id"], name: "index_entries_on_age_id"
    t.index ["follow_id"], name: "index_entries_on_follow_id"
    t.index ["instructor_id"], name: "index_entries_on_instructor_id"
    t.index ["lead_id"], name: "index_entries_on_lead_id"
    t.index ["level_id"], name: "index_entries_on_level_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.string "location"
    t.string "date"
    t.integer "heat_range_cat"
    t.integer "heat_range_level"
    t.integer "heat_range_age"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "intermix", default: true
    t.integer "current_heat"
    t.integer "ballrooms", default: 1
    t.integer "heat_length"
  end

  create_table "formations", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "solo_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_formations_on_person_id"
    t.index ["solo_id"], name: "index_formations_on_solo_id"
  end

  create_table "heats", force: :cascade do |t|
    t.integer "number"
    t.string "category"
    t.integer "dance_id", null: false
    t.integer "entry_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dance_id"], name: "index_heats_on_dance_id"
    t.index ["entry_id"], name: "index_heats_on_entry_id"
  end

  create_table "levels", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "people", force: :cascade do |t|
    t.string "name"
    t.integer "studio_id"
    t.string "type"
    t.integer "back"
    t.integer "level_id"
    t.integer "age_id"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["age_id"], name: "index_people_on_age_id"
    t.index ["level_id"], name: "index_people_on_level_id"
    t.index ["studio_id"], name: "index_people_on_studio_id"
  end

  create_table "scores", force: :cascade do |t|
    t.integer "judge_id", null: false
    t.integer "heat_id", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["heat_id"], name: "index_scores_on_heat_id"
    t.index ["judge_id"], name: "index_scores_on_judge_id"
  end

  create_table "solos", force: :cascade do |t|
    t.integer "heat_id", null: false
    t.integer "combo_dance_id"
    t.integer "order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "song"
    t.string "artist"
    t.index ["combo_dance_id"], name: "index_solos_on_combo_dance_id"
    t.index ["heat_id"], name: "index_solos_on_heat_id"
  end

  create_table "studio_pairs", force: :cascade do |t|
    t.integer "studio1_id", null: false
    t.integer "studio2_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["studio1_id"], name: "index_studio_pairs_on_studio1_id"
    t.index ["studio2_id"], name: "index_studio_pairs_on_studio2_id"
  end

  create_table "studios", force: :cascade do |t|
    t.string "name"
    t.integer "tables"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "dances", "categories", column: "closed_category_id"
  add_foreign_key "dances", "categories", column: "open_category_id"
  add_foreign_key "dances", "categories", column: "solo_category_id"
  add_foreign_key "entries", "ages"
  add_foreign_key "entries", "levels"
  add_foreign_key "entries", "people", column: "follow_id"
  add_foreign_key "entries", "people", column: "instructor_id"
  add_foreign_key "entries", "people", column: "lead_id"
  add_foreign_key "formations", "people"
  add_foreign_key "formations", "solos"
  add_foreign_key "heats", "dances"
  add_foreign_key "heats", "entries"
  add_foreign_key "people", "ages"
  add_foreign_key "people", "levels"
  add_foreign_key "people", "studios"
  add_foreign_key "scores", "heats"
  add_foreign_key "scores", "people", column: "judge_id"
  add_foreign_key "solos", "dances", column: "combo_dance_id"
  add_foreign_key "solos", "heats"
  add_foreign_key "studio_pairs", "studios", column: "studio1_id"
  add_foreign_key "studio_pairs", "studios", column: "studio2_id"
end
