class DatasetComparisonsController < ApplicationController
  before_action :load_datasets

  def index
    @dataset_a_id = strict_dataset_id(params[:dataset_a_id])
    @dataset_b_id = strict_dataset_id(params[:dataset_b_id])
    return if @dataset_a_id.blank? && @dataset_b_id.blank?

    selected_datasets = Dataset.where(id: [ @dataset_a_id, @dataset_b_id ].compact.uniq).index_by(&:id)
    @dataset_a = selected_datasets[@dataset_a_id]
    @dataset_b = selected_datasets[@dataset_b_id]

    if @dataset_a.blank? || @dataset_b.blank?
      @selection_error = "Choose two available datasets to compare."
    elsif @dataset_a == @dataset_b
      @selection_error = "Choose two different datasets to compare."
    else
      @comparison = DatasetComparison.call(dataset_a: @dataset_a, dataset_b: @dataset_b)
    end
  end

  private

  def load_datasets
    @datasets = Dataset.order(:name, :id)
  end

  def strict_dataset_id(value)
    Integer(value, 10) if value.present?
  rescue ArgumentError, TypeError
    nil
  end
end
