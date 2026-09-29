class CreateDatasets < ActiveRecord::Migration[8.1]
  def change
    create_table :datasets do |t|
      t.string :name, null: false
      t.string :source_organization
      t.string :source_url
      t.string :version
      t.text :description

      t.timestamps
    end
  end
end
