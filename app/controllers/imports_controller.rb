class ImportsController < ApplicationController
  before_action :set_dataset
  before_action :set_source_file

  def create
    import_run = SourceFileImporter.call(source_file: @source_file)
    redirect_to dataset_source_file_import_run_path(@dataset, @source_file, import_run),
      notice: import_run.completed? ? "Source file import completed." : nil,
      alert: import_run.failed? ? import_run.failure_message : nil
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:dataset_id])
  end

  def set_source_file
    @source_file = @dataset.source_files.find(params[:source_file_id])
  end
end
