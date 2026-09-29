require "csv"

class SourceFileInspector
  SAMPLE_SIZE = 5

  class Error < StandardError
  end

  def initialize(source_file_or_io)
    @source_file_or_io = source_file_or_io
  end

  def call
    if source_file?
      inspect_stored_source_file
    else
      inspect_io(@source_file_or_io)
    end
  rescue CSV::MalformedCSVError, ArgumentError, EncodingError => error
    raise Error, "The CSV could not be inspected: #{error.message}"
  end

  private

  def source_file?
    @source_file_or_io.respond_to?(:file)
  end

  def inspect_stored_source_file
    unless @source_file_or_io.file.attached?
      raise Error, "The source file is not available in local storage."
    end

    @source_file_or_io.file.open { |io| inspect_io(io) }
  rescue ActiveStorage::FileNotFoundError
    raise Error, "The source file is not available in local storage."
  end

  def inspect_io(io)
    io.rewind
    parser = CSV.new(io, headers: true, return_headers: false, liberal_parsing: false)
    first_row = parser.shift
    columns = parser.headers

    if columns == true || columns.blank?
      raise Error, "The CSV is empty or does not contain a header row."
    end

    columns = columns.map(&:to_s)
    row_count = 0
    sample_rows = []
    blank_counts = Array.new(columns.length, 0)
    warnings = structural_warnings(columns)

    process_row(first_row, columns, blank_counts, sample_rows, warnings) if first_row
    row_count += 1 if first_row

    while (row = parser.shift)
      process_row(row, columns, blank_counts, sample_rows, warnings)
      row_count += 1
    end

    warnings << "The file contains a header but no data rows." if row_count.zero?

    {
      columns: columns,
      row_count: row_count,
      sample_rows: sample_rows,
      blank_counts: blank_counts,
      warnings: warnings.uniq
    }
  end

  def process_row(row, columns, blank_counts, sample_rows, warnings)
    values = row.fields
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
