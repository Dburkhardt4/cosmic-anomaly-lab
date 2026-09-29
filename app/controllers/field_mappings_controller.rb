class FieldMappingsController < ApplicationController
  before_action :set_dataset
  before_action :set_source_file

  def edit
    load_mapping_context
  rescue SourceFileInspector::Error => error
    redirect_to [ @dataset, @source_file ], alert: error.message
  end

  def update
    load_mapping_context
    if duplicate_source_columns?
      @source_file.errors.add(:base, "Field mapping requires unique source column names. Resolve duplicate headers before saving.")
      return render :edit, status: :unprocessable_content
    end

    selected_concept_ids = selected_concept_ids_by_index
    return render :edit, status: :unprocessable_content if selected_concept_ids.nil?

    concepts_by_id = NormalizedConcept.where(id: selected_concept_ids.values.compact).index_by { |concept| concept.id.to_s }

    if concepts_by_id.size != selected_concept_ids.values.compact.uniq.size
      @source_file.errors.add(:base, "Choose an available normalized concept or leave the field unmapped.")
      return render :edit, status: :unprocessable_content
    end

    @source_file.transaction do
      @inspection[:columns].each_with_index do |source_column_name, index|
        normalized_concept = concepts_by_id[selected_concept_ids[index.to_s]]
        field_mapping = @source_file.field_mappings.find_or_initialize_by(source_column_name: source_column_name)
        field_mapping.assign_attributes(
          normalized_concept: normalized_concept,
          status: normalized_concept.present? ? :mapped : :unmapped
        )
        field_mapping.save!
      end
    end

    redirect_to edit_dataset_source_file_field_mapping_path(@dataset, @source_file), notice: "Field mappings saved."
  rescue SourceFileInspector::Error => error
    redirect_to [ @dataset, @source_file ], alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    @source_file.errors.add(:base, error.record.errors.full_messages.to_sentence)
    load_mapping_context
    render :edit, status: :unprocessable_content
  end

  private

  def set_dataset
    @dataset = Dataset.find(params[:dataset_id])
  end

  def set_source_file
    @source_file = @dataset.source_files.find(params[:source_file_id])
  end

  def load_mapping_context
    @inspection = SourceFileInspector.new(@source_file).call
    @normalized_concepts = NormalizedConcept.order(:name)
    @field_mappings_by_column = @source_file.field_mappings.includes(:normalized_concept).index_by(&:source_column_name)
  end

  def selected_concept_ids_by_index
    submitted_mappings = params[:field_mappings]
    unless submitted_mappings.is_a?(ActionController::Parameters)
      @source_file.errors.add(:base, "Field mapping parameters were invalid.")
      return
    end

    permitted_mappings = submitted_mappings.permit(*mapping_param_keys)

    mapping_param_keys.index_with { |key| permitted_mappings[key].presence }
  end

  def duplicate_source_columns?
    @inspection[:columns].uniq.length != @inspection[:columns].length
  end

  def mapping_param_keys
    @inspection[:columns].each_index.map(&:to_s)
  end
end
