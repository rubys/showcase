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

ActiveRecord::Schema[8.0].define(version: 2025_09_25_171325) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "age_costs", force: :cascade do |t|
    t.integer "age_id", null: false
    t.decimal "heat_cost", precision: 7, scale: 2
    t.decimal "solo_cost", precision: 7, scale: 2
    t.decimal "multi_cost", precision: 7, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["age_id"], name: "index_age_costs_on_age_id"
  end

  create_table "ages", force: :cascade do |t|
    t.string "category"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "billables", force: :cascade do |t|
    t.string "type"
    t.string "name"
    t.decimal "price", precision: 7, scale: 2
    t.integer "order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "couples", default: false
    t.integer "table_size"
  end

  create_table "cat_extensions", force: :cascade do |t|
    t.integer "category_id", null: false
    t.integer "start_heat"
    t.integer "part"
    t.integer "order"
    t.string "day"
    t.string "time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "duration"
    t.index ["category_id"], name: "index_cat_extensions_on_category_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.integer "order"
    t.string "day"
    t.string "time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ballrooms"
    t.integer "max_heat_size"
    t.boolean "routines"
    t.integer "duration"
    t.decimal "cost_override", precision: 7, scale: 2
    t.boolean "pro", default: false
    t.boolean "locked"
    t.decimal "studio_cost_override", precision: 7, scale: 2
    t.string "split"
  end

  create_table "dances", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "open_category_id"
    t.integer "closed_category_id"
    t.integer "order"
    t.integer "solo_category_id"
    t.integer "multi_category_id"
    t.integer "heat_length"
    t.integer "row"
    t.integer "col"
    t.decimal "cost_override", precision: 7, scale: 2
    t.integer "pro_open_category_id"
    t.integer "pro_closed_category_id"
    t.integer "pro_solo_category_id"
    t.integer "pro_multi_category_id"
    t.boolean "semi_finals", default: false
    t.integer "limit"
    t.index ["closed_category_id"], name: "index_dances_on_closed_category_id"
    t.index ["multi_category_id"], name: "index_dances_on_multi_category_id"
    t.index ["open_category_id"], name: "index_dances_on_open_category_id"
    t.index ["pro_closed_category_id"], name: "index_dances_on_pro_closed_category_id"
    t.index ["pro_multi_category_id"], name: "index_dances_on_pro_multi_category_id"
    t.index ["pro_open_category_id"], name: "index_dances_on_pro_open_category_id"
    t.index ["pro_solo_category_id"], name: "index_dances_on_pro_solo_category_id"
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
    t.decimal "heat_cost", precision: 7, scale: 2
    t.decimal "solo_cost", precision: 7, scale: 2
    t.decimal "multi_cost", precision: 7, scale: 2
    t.string "email"
    t.integer "max_heat_size"
    t.boolean "package_required", default: true
    t.boolean "backnums", default: true
    t.boolean "track_ages", default: true
    t.integer "column_order", default: 1
    t.string "open_scoring", default: "1"
    t.integer "solo_length"
    t.string "theme"
    t.boolean "locked", default: false
    t.string "student_package_description"
    t.string "payment_due"
    t.string "multi_scoring", default: "1"
    t.boolean "judge_comments", default: false
    t.boolean "agenda_based_entries", default: false
    t.boolean "pro_heats", default: false
    t.integer "assign_judges", default: 0
    t.string "font_size", default: "100%"
    t.boolean "include_times", default: true
    t.boolean "include_open", default: true
    t.boolean "include_closed", default: true
    t.integer "solo_level_id"
    t.boolean "print_studio_heats", default: false
    t.string "font_family", default: "Helvetica, Arial"
    t.boolean "independent_instructors", default: false
    t.string "closed_scoring", default: "G"
    t.string "heat_order", default: "L"
    t.integer "dance_limit"
    t.string "counter_color", default: "#FFFFFF"
    t.decimal "pro_heat_cost", precision: 7, scale: 2
    t.decimal "pro_solo_cost", precision: 7, scale: 2
    t.decimal "pro_multi_cost", precision: 7, scale: 2
    t.boolean "strict_scoring", default: false
    t.string "pro_am", default: "G"
    t.string "solo_scoring", default: "1"
    t.boolean "judge_recordings", default: false
    t.integer "table_size"
    t.string "finalist", default: "F"
    t.decimal "studio_formation_cost", precision: 7, scale: 2
    t.string "proam_studio_invoice", default: "A"
    t.index ["solo_level_id"], name: "index_events_on_solo_level_id"
  end

  create_table "feedbacks", force: :cascade do |t|
    t.integer "order"
    t.string "value"
    t.string "abbr"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "formations", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "solo_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "on_floor", default: true
    t.index ["person_id"], name: "index_formations_on_person_id"
    t.index ["solo_id"], name: "index_formations_on_solo_id"
  end

  create_table "heats", force: :cascade do |t|
    t.float "number"
    t.string "category"
    t.integer "dance_id", null: false
    t.integer "entry_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ballroom"
    t.float "prev_number"
    t.index ["dance_id"], name: "index_heats_on_dance_id"
    t.index ["entry_id"], name: "index_heats_on_entry_id"
  end

  create_table "judges", force: :cascade do |t|
    t.integer "person_id", null: false
    t.string "sort"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "show_assignments", default: "first", null: false
    t.boolean "present", default: true, null: false
    t.string "ballroom", default: "Both", null: false
    t.string "review_solos", default: "All"
    t.index ["person_id"], name: "index_judges_on_person_id"
  end

  create_table "levels", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "locations", force: :cascade do |t|
    t.string "key"
    t.string "name"
    t.string "logo"
    t.float "latitude"
    t.float "longitude"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "region"
    t.string "sisters"
    t.integer "trust_level", default: 0
    t.string "locale", default: "en_US"
    t.index ["user_id"], name: "index_locations_on_user_id"
  end

  create_table "multis", force: :cascade do |t|
    t.integer "parent_id", null: false
    t.integer "dance_id", null: false
    t.integer "slot"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dance_id"], name: "index_multis_on_dance_id"
    t.index ["parent_id"], name: "index_multis_on_parent_id"
  end

  create_table "package_includes", force: :cascade do |t|
    t.integer "package_id", null: false
    t.integer "option_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["option_id"], name: "index_package_includes_on_option_id"
    t.index ["package_id"], name: "index_package_includes_on_package_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "person_id", null: false
    t.decimal "amount"
    t.date "date"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_payments_on_person_id"
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
    t.integer "exclude_id"
    t.integer "package_id"
    t.boolean "independent", default: false
    t.integer "invoice_to_id"
    t.string "available"
    t.integer "table_id"
    t.index ["age_id"], name: "index_people_on_age_id"
    t.index ["exclude_id"], name: "index_people_on_exclude_id"
    t.index ["invoice_to_id"], name: "index_people_on_invoice_to_id"
    t.index ["level_id"], name: "index_people_on_level_id"
    t.index ["package_id"], name: "index_people_on_package_id"
    t.index ["studio_id"], name: "index_people_on_studio_id"
    t.index ["table_id"], name: "index_people_on_table_id"
  end

  create_table "person_options", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "option_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "table_id"
    t.index ["option_id"], name: "index_person_options_on_option_id"
    t.index ["person_id"], name: "index_person_options_on_person_id"
    t.index ["table_id"], name: "index_person_options_on_table_id"
  end

  create_table "recordings", force: :cascade do |t|
    t.integer "judge_id", null: false
    t.integer "heat_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["heat_id"], name: "index_recordings_on_heat_id"
    t.index ["judge_id"], name: "index_recordings_on_judge_id"
  end

  create_table "regions", force: :cascade do |t|
    t.string "type"
    t.string "code"
    t.string "location"
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "scores", force: :cascade do |t|
    t.integer "judge_id", null: false
    t.integer "heat_id", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "slot"
    t.string "comments"
    t.string "good"
    t.string "bad"
    t.index ["heat_id"], name: "index_scores_on_heat_id"
    t.index ["judge_id"], name: "index_scores_on_judge_id"
  end

  create_table "showcases", force: :cascade do |t|
    t.integer "year"
    t.string "key"
    t.string "name"
    t.integer "location_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.string "date"
    t.index ["location_id"], name: "index_showcases_on_location_id"
  end

  create_table "solos", force: :cascade do |t|
    t.integer "heat_id", null: false
    t.integer "combo_dance_id"
    t.integer "order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "song"
    t.string "artist"
    t.integer "category_override_id"
    t.index ["category_override_id"], name: "index_solos_on_category_override_id"
    t.index ["combo_dance_id"], name: "index_solos_on_combo_dance_id"
    t.index ["heat_id"], name: "index_solos_on_heat_id"
  end

  create_table "songs", force: :cascade do |t|
    t.integer "dance_id", null: false
    t.integer "order"
    t.string "title"
    t.string "artist"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dance_id"], name: "index_songs_on_dance_id"
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
    t.decimal "heat_cost", precision: 7, scale: 2
    t.decimal "solo_cost", precision: 7, scale: 2
    t.decimal "multi_cost", precision: 7, scale: 2
    t.string "email"
    t.integer "default_student_package_id"
    t.integer "default_professional_package_id"
    t.integer "default_guest_package_id"
    t.decimal "student_registration_cost", precision: 7, scale: 2
    t.decimal "student_heat_cost", precision: 7, scale: 2
    t.decimal "student_solo_cost", precision: 7, scale: 2
    t.decimal "student_multi_cost", precision: 7, scale: 2
    t.string "ballroom"
    t.index ["default_guest_package_id"], name: "index_studios_on_default_guest_package_id"
    t.index ["default_professional_package_id"], name: "index_studios_on_default_professional_package_id"
    t.index ["default_student_package_id"], name: "index_studios_on_default_student_package_id"
  end

  create_table "tables", force: :cascade do |t|
    t.integer "number"
    t.integer "row"
    t.integer "col"
    t.integer "size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "option_id"
    t.boolean "locked", default: false
    t.index ["option_id"], name: "index_tables_on_option_id"
    t.index ["row", "col", "option_id"], name: "index_tables_on_row_and_col_and_option_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "userid"
    t.string "password"
    t.string "email"
    t.string "name1"
    t.string "name2"
    t.string "token"
    t.string "link"
    t.string "sites"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "age_costs", "ages"
  add_foreign_key "cat_extensions", "categories"
  add_foreign_key "dances", "categories", column: "closed_category_id"
  add_foreign_key "dances", "categories", column: "multi_category_id"
  add_foreign_key "dances", "categories", column: "open_category_id"
  add_foreign_key "dances", "categories", column: "pro_closed_category_id"
  add_foreign_key "dances", "categories", column: "pro_multi_category_id"
  add_foreign_key "dances", "categories", column: "pro_open_category_id"
  add_foreign_key "dances", "categories", column: "pro_solo_category_id"
  add_foreign_key "dances", "categories", column: "solo_category_id"
  add_foreign_key "entries", "ages"
  add_foreign_key "entries", "levels"
  add_foreign_key "entries", "people", column: "follow_id"
  add_foreign_key "entries", "people", column: "instructor_id"
  add_foreign_key "entries", "people", column: "lead_id"
  add_foreign_key "events", "levels", column: "solo_level_id"
  add_foreign_key "formations", "people"
  add_foreign_key "formations", "solos"
  add_foreign_key "heats", "dances"
  add_foreign_key "heats", "entries"
  add_foreign_key "judges", "people"
  add_foreign_key "locations", "users"
  add_foreign_key "multis", "dances"
  add_foreign_key "multis", "dances", column: "parent_id"
  add_foreign_key "package_includes", "billables", column: "option_id"
  add_foreign_key "package_includes", "billables", column: "package_id"
  add_foreign_key "payments", "people"
  add_foreign_key "people", "ages"
  add_foreign_key "people", "billables", column: "package_id"
  add_foreign_key "people", "levels"
  add_foreign_key "people", "people", column: "exclude_id"
  add_foreign_key "people", "people", column: "invoice_to_id"
  add_foreign_key "people", "studios"
  add_foreign_key "people", "tables"
  add_foreign_key "person_options", "billables", column: "option_id"
  add_foreign_key "person_options", "people"
  add_foreign_key "person_options", "tables"
  add_foreign_key "recordings", "heats"
  add_foreign_key "recordings", "judges"
  add_foreign_key "scores", "heats"
  add_foreign_key "scores", "people", column: "judge_id"
  add_foreign_key "showcases", "locations"
  add_foreign_key "solos", "categories", column: "category_override_id"
  add_foreign_key "solos", "dances", column: "combo_dance_id"
  add_foreign_key "solos", "heats"
  add_foreign_key "songs", "dances"
  add_foreign_key "studio_pairs", "studios", column: "studio1_id"
  add_foreign_key "studio_pairs", "studios", column: "studio2_id"
  add_foreign_key "studios", "billables", column: "default_guest_package_id"
  add_foreign_key "studios", "billables", column: "default_professional_package_id"
  add_foreign_key "studios", "billables", column: "default_student_package_id"
  add_foreign_key "tables", "billables", column: "option_id"
end
