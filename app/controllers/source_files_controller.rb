class SourceFilesController < ApplicationController
  before_action :set_dataset

  def create
    @source_file = SourceFileUploader.call(dataset: @dataset, upload: source_file_params[:file])

    redirect_to [ @dataset, @source_file ], notice: "Source CSV attached. It has not been imported or normalized."
  rescue SourceFileUploader::Error => error
    @source_files = @dataset.source_files.order(created_at: :desc)
    @imported_record_count = @dataset.normalized_records.count
    @source_file = @dataset.source_files.build
    @source_file.errors.add(:file, error.message)
    render "datasets/show", status: :unprocessable_content
  end

  def show
    @source_file = @dataset.source_files.find(params[:id])
    @import_run = @source_file.import_runs.first
    @inspection = SourceFileInspector.new(@source_file).call
  rescue SourceFileInspector::Error => error
    redirect_to @dataset, alert: error.message
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:dataset_id])
  end

  def source_file_params
    params.expect(source_file: [ :file ])
  end
end
