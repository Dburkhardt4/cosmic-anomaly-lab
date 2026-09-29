class SourceFileMappingContext
  VALID_MAPPING_STATUSES = %w[mapped unmapped].freeze

  def self.call(source_file:, columns:)
    new(source_file, columns).call
  end

  def initialize(source_file, columns)
    @source_file = source_file
    @columns = columns
  end

  def call
    mappings = @source_file.field_mappings.includes(:normalized_concept).to_a
    issues = duplicate_source_column_issues + duplicate_mapping_issues(mappings)
    concepts_by_id = normalized_concepts_by_id(mappings)
    mapped_by_column = {}

    mappings.each do |mapping|
      source_column_name = mapping.source_column_name
      status = mapping[:status].to_s
      concept_id = mapping.normalized_concept_id

      if source_column_name.nil? || !VALID_MAPPING_STATUSES.include?(status)
        issues << invalid_mapping_issue(mapping)
        next
      end

      next if duplicate_mapping_names.include?(source_column_name)
      next if duplicate_source_columns.include?(source_column_name)

      if status == "mapped"
        if concept_id.blank?
          issues << invalid_mapping_issue(mapping)
        elsif !concepts_by_id.key?(concept_id)
          issues << ImportPreviewIssue.new(
            severity: :error,
            code: :unknown_normalized_concept,
            message: "The saved mapping for #{source_column_label(source_column_name)} references an unavailable normalized concept.",
            source_column_name: source_column_name
          )
        elsif !@columns.include?(source_column_name)
          issues << ImportPreviewIssue.new(
            severity: :error,
            code: :mapped_source_column_missing,
            message: "Mapped source column #{source_column_label(source_column_name)} is not present in this CSV.",
            source_column_name: source_column_name
          )
        else
          mapped_by_column[source_column_name] = {
            concept: concepts_by_id[concept_id],
            source_column_name: source_column_name
          }
        end
      elsif concept_id.present?
        issues << invalid_mapping_issue(mapping)
      end
    end

    unmapped_columns = @columns.reject { |source_column_name| mapped_by_column.key?(source_column_name) }
    issues.concat(unmapped_columns.uniq.map do |source_column_name|
      ImportPreviewIssue.new(
        severity: :info,
        code: :unmapped_source_column,
        message: "Source column #{source_column_label(source_column_name)} remains unmapped.",
        source_column_name: source_column_name
      )
    end)

    {
      issues: issues,
      mapped_by_column: mapped_by_column,
      mapped_concepts: mapped_by_column.values.map { |mapping| mapping[:concept] }.uniq
    }
  end

  private

  def duplicate_source_columns
    @duplicate_source_columns ||= @columns.group_by(&:itself).select { |_name, values| values.length > 1 }.keys
  end

  def duplicate_source_column_issues
    duplicate_source_columns.map do |source_column_name|
      ImportPreviewIssue.new(
        severity: :error,
        code: :duplicate_source_column_name,
        message: "The CSV contains more than one source column named #{source_column_label(source_column_name)}; it cannot be mapped unambiguously.",
        source_column_name: source_column_name
      )
    end
  end

  def duplicate_mapping_names
    @duplicate_mapping_names ||= @source_file.field_mappings.group(:source_column_name).having("COUNT(*) > 1").pluck(:source_column_name)
  end

  def duplicate_mapping_issues(mappings)
    mappings.group_by(&:source_column_name).select { |_name, records| records.length > 1 }.keys.map do |source_column_name|
      ImportPreviewIssue.new(
        severity: :error,
        code: :duplicate_field_mapping,
        message: "More than one saved mapping exists for source column #{source_column_label(source_column_name)}.",
        source_column_name: source_column_name
      )
    end
  end

  def normalized_concepts_by_id(mappings)
    concept_ids = mappings.filter_map(&:normalized_concept_id).uniq
    NormalizedConcept.where(id: concept_ids).index_by(&:id)
  end

  def invalid_mapping_issue(mapping)
    ImportPreviewIssue.new(
      severity: :error,
      code: :invalid_mapping_state,
      message: "The saved mapping for #{source_column_label(mapping.source_column_name)} is incomplete or inconsistent.",
      source_column_name: mapping.source_column_name
    )
  end

  def source_column_label(source_column_name)
    source_column_name.presence || "(blank source name)"
  end
end
