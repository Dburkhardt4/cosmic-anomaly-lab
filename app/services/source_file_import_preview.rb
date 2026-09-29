class SourceFileImportPreview
  DEFAULT_ROW_LIMIT = 20
  VALID_MAPPING_STATUSES = %w[mapped unmapped].freeze

  def self.call(source_file:, row_limit: DEFAULT_ROW_LIMIT)
    new(source_file, row_limit: row_limit).call
  end

  def initialize(source_file, row_limit: DEFAULT_ROW_LIMIT)
    @source_file = source_file
    @row_limit = Integer(row_limit)
    raise ArgumentError, "The preview row limit must be zero or greater." if @row_limit.negative?
  end

  def call
    @row_shape_issues_by_row = Hash.new { |issues, row_number| issues[row_number] = [] }
    @global_row_issues = []

    csv = read_csv
    columns = csv[:columns] || []
    mapping_context = mapping_context_for(columns)
    global_issues = integrity_issues + @csv_issues + @global_row_issues + mapping_context[:issues]
    rows = csv[:rows].map { |row| build_preview_row(row, columns, mapping_context, global_issues) }

    {
      source_file: @source_file,
      columns: columns,
      rows: rows,
      issues: global_issues,
      summary: build_summary(csv, columns, rows, global_issues, mapping_context)
    }
  end

  private

  def read_csv
    @csv_issues = []

    SourceFileCsvReader.new(@source_file).read(limit: @row_limit) do |columns, values, row_number|
      next if values.length == columns.length

      issue = ImportPreviewIssue.new(
        severity: :error,
        code: :malformed_csv_row,
        message: "Source row #{row_number} contains #{values.length} values for #{columns.length} columns.",
        source_row_number: row_number
      )
      @row_shape_issues_by_row[row_number] << issue
      @global_row_issues << issue if row_number > @row_limit
    end
  rescue SourceFileCsvReader::Error => error
    @csv_issues << ImportPreviewIssue.new(
      severity: :error,
      code: error.code,
      message: error.message
    )

    { columns: error.columns || [], rows: error.rows || [], row_count: error.row_count }
  end

  def integrity_issues
    checksum = SourceFileChecksum.for_source_file(@source_file)
    issues = []

    if checksum[:byte_size] != @source_file.byte_size
      issues << ImportPreviewIssue.new(
        severity: :error,
        code: :source_file_size_mismatch,
        message: "The stored source-file size does not match the attached file."
      )
    end

    if checksum[:sha256] != @source_file.sha256
      issues << ImportPreviewIssue.new(
        severity: :error,
        code: :source_file_hash_mismatch,
        message: "The stored source-file hash does not match the attached file."
      )
    end

    issues
  rescue SourceFileChecksum::Error => error
    [ ImportPreviewIssue.new(severity: :error, code: :source_file_unavailable, message: error.message) ]
  end

  def mapping_context_for(columns)
    mappings = @source_file.field_mappings.includes(:normalized_concept).to_a
    issues = []
    duplicate_source_columns = columns.group_by(&:itself).select { |_name, column_values| column_values.length > 1 }.keys
    duplicate_source_columns.each do |source_column_name|
      issues << ImportPreviewIssue.new(
        severity: :error,
        code: :duplicate_source_column_name,
        message: "The CSV contains more than one source column named #{source_column_label(source_column_name)}; it cannot be mapped unambiguously.",
        source_column_name: source_column_name
      )
    end

    duplicate_names = mappings.group_by(&:source_column_name).select { |_name, records| records.length > 1 }.keys
    duplicate_names.each do |source_column_name|
      issues << ImportPreviewIssue.new(
        severity: :error,
        code: :duplicate_field_mapping,
        message: "More than one saved mapping exists for source column #{source_column_label(source_column_name)}.",
        source_column_name: source_column_name
      )
    end

    concept_ids = mappings.filter_map(&:normalized_concept_id).uniq
    concepts_by_id = NormalizedConcept.where(id: concept_ids).index_by(&:id)
    mapped_by_column = {}

    mappings.each do |mapping|
      source_column_name = mapping.source_column_name
      status = mapping[:status].to_s
      concept_id = mapping.normalized_concept_id

      if source_column_name.nil? || !VALID_MAPPING_STATUSES.include?(status)
        issues << invalid_mapping_issue(mapping)
        next
      end

      if duplicate_names.include?(source_column_name)
        next
      end

      if duplicate_source_columns.include?(source_column_name)
        next
      end

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
        elsif !columns.include?(source_column_name)
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

    unmapped_columns = columns.reject { |source_column_name| mapped_by_column.key?(source_column_name) }
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

  def build_preview_row(row, columns, mapping_context, global_issues)
    values = row[:values]
    row_number = row[:number]
    issues = @row_shape_issues_by_row[row_number].dup
    mapped_values = []
    unmapped_values = []

    columns.each_with_index do |source_column_name, index|
      value = values[index]
      mapping = mapping_context[:mapped_by_column][source_column_name]

      if mapping
        mapped_values << {
          source_column_name: source_column_name,
          concept: mapping[:concept],
          value: value
        }
        if blank_value?(value)
          issues << ImportPreviewIssue.new(
            severity: :warning,
            code: :blank_mapped_value,
            message: "Mapped source column #{source_column_label(source_column_name)} is blank for this row.",
            source_column_name: source_column_name,
            source_row_number: row_number
          )
        end
      else
        unmapped_values << { source_column_name: source_column_name, value: value }
      end
    end

    {
      source_row_number: row_number,
      source_values: values,
      mapped_values: mapped_values,
      unmapped_values: unmapped_values,
      issues: issues,
      importable: !global_issues.any?(&:error?) && !issues.any?(&:error?)
    }
  end

  def build_summary(csv, columns, rows, global_issues, mapping_context)
    global_error = global_issues.any?(&:error?)
    normalized_concepts = mapping_context[:mapped_concepts].map do |concept|
      { key: concept.key, name: concept.name }
    end

    {
      source_filename: @source_file.original_filename,
      total_source_row_count: csv[:row_count],
      rows_previewed: rows.length,
      rows_with_errors: rows.count { |row| global_error || row[:issues].any?(&:error?) },
      rows_with_warnings: rows.count { |row| row[:issues].any?(&:warning?) },
      mapped_column_count: mapping_context[:mapped_by_column].length,
      unmapped_column_count: columns.length - mapping_context[:mapped_by_column].length,
      normalized_concepts: normalized_concepts
    }
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

  def blank_value?(value)
    value.nil? || value == ""
  end
end
