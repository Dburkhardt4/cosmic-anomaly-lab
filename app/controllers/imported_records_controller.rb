class ImportedRecordsController < ApplicationController
  PER_PAGE = 25

  before_action :set_dataset
  before_action :load_exploration_context, only: :index
  before_action :set_record, only: :show

  def index
    @records = filtered_records
      .includes(imported_source_record: %i[source_file import_run])
      .order(:id)

    @total_record_count = @records.count
    @total_pages = (@total_record_count.to_f / PER_PAGE).ceil
    @page = normalized_page
    @page = @total_pages if @total_pages.positive? && @page > @total_pages
    @records = @records.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def show
    @source_record = @record.imported_source_record
    @source_file = @source_record.source_file
    @import_run = @source_record.import_run
    concept_keys = @record.normalized_values.filter_map { |value| value["concept_key"] }.uniq
    @concepts_by_key = NormalizedConcept.where(key: concept_keys).index_by(&:key)
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:dataset_id])
  end

  def set_record
    @record = @dataset.normalized_records
      .includes(imported_source_record: %i[source_file import_run])
      .find(params[:id])
  end

  def load_exploration_context
    @source_files = @dataset.source_files.order(:original_filename, :id)
    @source_file_id = valid_source_file_id
    @record_types = @dataset.normalized_records.distinct.order(:record_type).pluck(:record_type)
    @record_type = params[:record_type].presence
    @query = params[:query].presence || params[:q].presence
    @concepts = @dataset.field_mappings
      .where(status: FieldMapping.statuses.fetch("mapped"))
      .includes(:normalized_concept)
      .filter_map(&:normalized_concept)
      .uniq(&:key)
      .sort_by(&:name)
  end

  def filtered_records
    scope = @dataset.normalized_records
    scope = scope.where(source_files: { id: @source_file_id }) if @source_file_id
    scope = scope.where(record_type: @record_type) if @record_type.present?
    scope.matching_normalized_values(@query)
  end

  def valid_source_file_id
    candidate = params[:source_file_id].to_i
    candidate if candidate.positive? && @source_files.any? { |source_file| source_file.id == candidate }
  end

  def normalized_page
    [ params[:page].to_i, 1 ].max
  end
end
