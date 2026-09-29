class CreateSourceFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :source_files do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :original_filename, null: false
      t.string :sha256, null: false
      t.bigint :byte_size, null: false

      t.timestamps
    end

    add_index :source_files, :sha256
  end
end
