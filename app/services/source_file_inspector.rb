class SourceFileInspector
  SAMPLE_SIZE = 5

  class Error < StandardError
  end

  def initialize(source_file_or_io)
    @source_file_or_io = source_file_or_io
  end

  def call
    sample_rows = []
    blank_counts = nil
    row_warnings = []

    csv = SourceFileCsvReader.new(@source_file_or_io).read(limit: SAMPLE_SIZE) do |columns, values, _row_number|
      blank_counts ||= Array.new(columns.length, 0)
      process_row(values, columns, blank_counts, sample_rows, row_warnings)
    end

    columns = csv[:columns]
    blank_counts ||= Array.new(columns.length, 0)
    warnings = structural_warnings(columns) + row_warnings
    warnings << "The file contains a header but no data rows." if csv[:row_count].zero?

    {
      columns: columns,
      row_count: csv[:row_count],
      sample_rows: sample_rows,
      blank_counts: blank_counts,
      warnings: warnings.uniq
    }
  rescue SourceFileCsvReader::Error => error
    raise Error, "The CSV could not be inspected: #{error.message}"
  end

  private

  def process_row(values, columns, blank_counts, sample_rows, warnings)
    warnings << "Some rows contain a different number of values than the header." if values.length != columns.length

    columns.each_index do |index|
      blank_counts[index] += 1 if values[index].nil? || values[index] == ""
    end

    sample_rows << values if sample_rows.length < SAMPLE_SIZE
  end

  def structural_warnings(columns)
    warnings = []
    warnings << "One or more source columns have a blank name." if columns.any?(&:blank?)
    warnings << "Two or more source columns share the same name; names remain unchanged." if columns.compact.uniq.length != columns.compact.length
    warnings
  end
end
