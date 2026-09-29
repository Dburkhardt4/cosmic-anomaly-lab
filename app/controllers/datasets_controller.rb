class DatasetsController < ApplicationController
  before_action :set_dataset, only: %i[show edit update]

  def index
    @datasets = Dataset.order(updated_at: :desc)
  end

  def show
    @source_files = @dataset.source_files.includes(:import_runs).order(created_at: :desc)
    @source_file = @dataset.source_files.build
  end

  def new
    @dataset = Dataset.new
  end

  def create
    @dataset = Dataset.new(dataset_params)

    if @dataset.save
      redirect_to @dataset, notice: "Dataset created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @dataset.update(dataset_params)
      redirect_to @dataset, notice: "Dataset updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:id])
  end

  def dataset_params
    params.expect(dataset: %i[name source_organization source_url version description])
  end
end
