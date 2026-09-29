class ImportPreviewsController < ApplicationController
  before_action :set_dataset
  before_action :set_source_file

  def show
    @import_run = @source_file.import_runs.first
    @preview = SourceFileImportPreview.call(source_file: @source_file)
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:dataset_id])
  end

  def set_source_file
    @source_file = @dataset.source_files.find(params[:source_file_id])
  end
end
