class CreateNormalizedConceptsAndFieldMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :normalized_concepts do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description, null: false
      t.string :expected_value_type
      t.string :canonical_unit
      t.text :notes

      t.timestamps
    end

    add_index :normalized_concepts, :key, unique: true

    create_table :field_mappings do |t|
      t.references :source_file, null: false, foreign_key: true
      t.string :source_column_name, null: false
      t.references :normalized_concept, foreign_key: true
      t.string :status, null: false, default: "unmapped"

      t.timestamps
    end

    add_index :field_mappings, [ :source_file_id, :source_column_name ],
      unique: true, name: :index_field_mappings_on_source_file_and_column
  end
end
