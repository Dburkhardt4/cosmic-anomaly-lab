class ImportRunsController < ApplicationController
  before_action :set_dataset
  before_action :set_source_file
  before_action :set_import_run

  def show
    @rejected_records = @import_run.imported_source_records.rejected.order(:source_row_number).limit(20)
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:dataset_id])
  end

  def set_source_file
    @source_file = @dataset.source_files.find(params[:source_file_id])
  end

  def set_import_run
    @import_run = @source_file.import_runs.find(params[:id])
  end
end
