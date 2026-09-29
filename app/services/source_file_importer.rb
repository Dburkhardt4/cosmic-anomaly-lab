class SourceFileImporter
  IMPORTER_VERSION = "1"
  STALE_RUN_AFTER = 1.hour

  class Failure < StandardError
    attr_reader :issues

    def initialize(message, issues: [])
      super(message)
      @issues = issues
    end
  end

  def self.call(source_file:)
    new(source_file).call
  end

  def initialize(source_file)
    @source_file = source_file
  end

  def call
    run, should_execute = prepare_import_run
    return run unless should_execute

    reset_counters
    perform_import(run)
  rescue StandardError => error
    fail_run(run, error)
  ensure
    run&.reload if run&.persisted?
  end

  private

  def prepare_import_run
    result = nil
    @source_file.with_lock do
      run = @source_file.import_runs.first

      if run&.completed?
        result = [ run, false ]
        next
      end

      if run&.importing? && !stale_import_run?(run)
        result = [ run, false ]
        next
      end

      run ||= @source_file.import_runs.build
      run.assign_attributes(
        status: :importing,
        started_at: Time.current,
        completed_at: nil,
        rows_read: 0,
        rows_imported: 0,
        rows_rejected: 0,
        warning_count: 0,
        error_count: 0,
        importer_version: IMPORTER_VERSION,
        failure_message: nil,
        validation_issues: [],
        source_sha256: nil,
        source_byte_size: nil
      )
      run.save!
      result = [ run, true ]
    end
    result
  end

  def perform_import(run)
    @mapping_context = nil

    validate_source_file_integrity!

    ApplicationRecord.transaction do
      csv = SourceFileCsvReader.new(@source_file).read(limit: nil) do |columns, values, row_number|
        @mapping_context ||= mapping_context_for(columns)
        validate_mapping_context!
        import_row(run, columns, values, row_number)
      end

      @mapping_context ||= mapping_context_for(csv[:columns] || [])
      validate_mapping_context!
      complete_run!(run)
    end

    run
  end

  def validate_source_file_integrity!
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

    raise Failure.new("The source file failed integrity validation.", issues: issues) if issues.any?

    @import_checksum = checksum
  rescue SourceFileChecksum::Error => error
    issue = ImportPreviewIssue.new(
      severity: :error,
      code: :source_file_unavailable,
      message: error.message
    )
    raise Failure.new(error.message, issues: [ issue ])
  end

  def mapping_context_for(columns)
    SourceFileMappingContext.call(source_file: @source_file, columns: columns)
  end

  def validate_mapping_context!
    issues = @mapping_context[:issues].select(&:error?)
    return if issues.empty?

    raise Failure.new("The saved field mappings are not valid for this source file.", issues: issues)
  end

  def import_row(run, columns, values, row_number)
    @rows_read += 1
    row_issues = []
    mapped_values = []
    unmapped_values = []

    columns.each_with_index do |source_column_name, index|
      value = values[index]
      mapping = @mapping_context[:mapped_by_column][source_column_name]

      if mapping
        mapped_values << normalized_value(mapping, value)
        row_issues << blank_value_issue(source_column_name, row_number) if blank_value?(value)
      else
        unmapped_values << source_value(source_column_name, value)
      end
    end

    values.each_with_index do |value, index|
      next if index < columns.length

      unmapped_values << source_value(nil, value, source_position: index + 1)
    end

    if values.length != columns.length
      row_issues << ImportPreviewIssue.new(
        severity: :error,
        code: :malformed_csv_row,
        message: "Source row #{row_number} contains #{values.length} values for #{columns.length} columns.",
        source_row_number: row_number
      )
    end

    payload = original_row_payload(columns, values)
    issue_payloads = row_issues.map { |issue| serialize_issue(issue) }
    imported_source_record = ImportedSourceRecord.create!(
      source_file: @source_file,
      import_run: run,
      source_row_number: row_number,
      original_row_payload: payload,
      status: row_issues.any?(&:error?) ? :rejected : :accepted,
      validation_issues: issue_payloads
    )

    @warning_count += row_issues.count(&:warning?)
    @error_count += row_issues.count(&:error?)

    if row_issues.any?(&:error?)
      @rows_rejected += 1
    else
      NormalizedRecord.create!(
        imported_source_record: imported_source_record,
        record_type: "generic",
        normalized_values: mapped_values,
        unmapped_values: unmapped_values,
        field_mapping_snapshot: mapping_snapshot(columns)
      )
      @rows_imported += 1
    end
  end

  def normalized_value(mapping, value)
    {
      "concept_key" => mapping[:concept].key,
      "concept_name" => mapping[:concept].name,
      "source_column_name" => mapping[:source_column_name],
      "value" => value
    }
  end

  def source_value(source_column_name, value, source_position: nil)
    entry = {
      "source_column_name" => source_column_name,
      "value" => value
    }
    entry["source_position"] = source_position if source_position
    entry
  end

  def mapping_snapshot(columns)
    columns.map do |source_column_name|
      mapping = @mapping_context[:mapped_by_column][source_column_name]
      {
        "source_column_name" => source_column_name,
        "status" => mapping ? "mapped" : "unmapped",
        "normalized_concept_key" => mapping&.dig(:concept)&.key,
        "normalized_concept_name" => mapping&.dig(:concept)&.name
      }
    end
  end

  def original_row_payload(columns, values)
    {
      "source_columns" => columns,
      "values" => values
    }
  end

  def blank_value_issue(source_column_name, row_number)
    ImportPreviewIssue.new(
      severity: :warning,
      code: :blank_mapped_value,
      message: "Mapped source column #{source_column_name.presence || "(blank source name)"} is blank for this row.",
      source_column_name: source_column_name,
      source_row_number: row_number
    )
  end

  def serialize_issue(issue)
    {
      "severity" => issue.severity,
      "code" => issue.code,
      "message" => issue.message,
      "source_column_name" => issue.source_column_name,
      "source_row_number" => issue.source_row_number
    }.compact
  end

  def complete_run!(run)
    run.update!(
      status: :completed,
      completed_at: Time.current,
      rows_read: @rows_read,
      rows_imported: @rows_imported,
      rows_rejected: @rows_rejected,
      warning_count: @warning_count,
      error_count: @error_count,
      failure_message: nil,
      validation_issues: [],
      source_sha256: @import_checksum[:sha256],
      source_byte_size: @import_checksum[:byte_size]
    )
  end

  def fail_run(run, error)
    return unless run&.persisted?

    issue_count = error.respond_to?(:issues) ? error.issues.count(&:error?) : 0
    run.update_columns(
      status: "failed",
      completed_at: Time.current,
      rows_read: @rows_read || 0,
      rows_imported: 0,
      rows_rejected: 0,
      warning_count: @warning_count || 0,
      error_count: [ @error_count || 0, issue_count, 1 ].max,
      failure_message: error.message,
      validation_issues: failure_issue_payloads(error),
      updated_at: Time.current
    )
    run
  end

  def reset_counters
    @rows_read = 0
    @rows_imported = 0
    @rows_rejected = 0
    @warning_count = 0
    @error_count = 0
  end

  def stale_import_run?(run)
    return true if run.pending?
    return false unless run.started_at.present? && run.started_at < STALE_RUN_AFTER.ago

    !run.imported_source_records.exists?
  end

  def failure_issue_payloads(error)
    issues = if error.respond_to?(:issues) && error.issues.present?
      error.issues
    else
      [ ImportPreviewIssue.new(
        severity: :error,
        code: error.respond_to?(:code) ? error.code : :import_failed,
        message: error.message.presence || "The source-file import failed."
      ) ]
    end

    issues.map { |issue| serialize_issue(issue) }
  end

  def blank_value?(value)
    value.nil? || value == ""
  end
end
