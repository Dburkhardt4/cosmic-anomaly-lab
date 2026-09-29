class AddSourceIntegrityToImportRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :import_runs, :source_sha256, :string
    add_column :import_runs, :source_byte_size, :bigint
  end
end
