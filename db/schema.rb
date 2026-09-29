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

ActiveRecord::Schema[8.1].define(version: 2026_09_29_120000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.integer "blob_id", null: false
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
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "datasets", force: :cascade do |t|
    t.string "name", null: false
    t.string "source_organization"
    t.string "source_url"
    t.string "version"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "field_mappings", force: :cascade do |t|
    t.integer "source_file_id", null: false
    t.string "source_column_name", null: false
    t.integer "normalized_concept_id"
    t.string "status", default: "unmapped", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_concept_id"], name: "index_field_mappings_on_normalized_concept_id"
    t.index ["source_file_id", "source_column_name"], name: "index_field_mappings_on_source_file_and_column", unique: true
    t.index ["source_file_id"], name: "index_field_mappings_on_source_file_id"
  end

  create_table "normalized_concepts", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description", null: false
    t.string "expected_value_type"
    t.string "canonical_unit"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_normalized_concepts_on_key", unique: true
  end

  create_table "source_files", force: :cascade do |t|
    t.integer "dataset_id", null: false
    t.string "original_filename", null: false
    t.string "sha256", null: false
    t.bigint "byte_size", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_source_files_on_dataset_id"
    t.index ["sha256"], name: "index_source_files_on_sha256"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "field_mappings", "normalized_concepts"
  add_foreign_key "field_mappings", "source_files"
  add_foreign_key "source_files", "datasets"
end
