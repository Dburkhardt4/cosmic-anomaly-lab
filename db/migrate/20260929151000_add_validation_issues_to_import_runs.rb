class AddValidationIssuesToImportRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :import_runs, :validation_issues, :json, null: false, default: []
  end
end
