class SourceFileImportPreview
  DEFAULT_ROW_LIMIT = 20

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
    mapping_context = SourceFileMappingContext.call(source_file: @source_file, columns: columns)
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

  def blank_value?(value)
    value.nil? || value == ""
  end

  def source_column_label(source_column_name)
    source_column_name.presence || "(blank source name)"
  end
end
