require "csv"

class SourceFileCsvReader
  class Error < StandardError
    attr_reader :code, :columns, :rows, :row_count

    def initialize(message, code:, columns: nil, rows: [], row_count: 0)
      super(message)
      @code = code
      @columns = columns
      @rows = rows
      @row_count = row_count
    end
  end

  def initialize(source_file_or_io)
    @source_file_or_io = source_file_or_io
  end

  def read(limit: nil)
    row_limit = normalize_limit(limit)
    columns = nil
    rows = []
    row_count = 0

    with_source_io do |io|
      io.rewind
      parser = CSV.new(io, headers: true, return_headers: false, liberal_parsing: false)
      first_row = parser.shift
      columns = parser.headers

      validate_columns!(columns)
      columns = columns.map(&:to_s)

      row_count = append_row(first_row, columns, row_count, rows, row_limit) do |values, number|
        yield columns, values, number if block_given?
      end

      while (row = parser.shift)
        row_count = append_row(row, columns, row_count, rows, row_limit) do |values, number|
          yield columns, values, number if block_given?
        end
      end
    end

    { columns: columns, rows: rows, row_count: row_count }
  rescue CSV::MalformedCSVError, ArgumentError, EncodingError => error
    raise Error.new(
      "The CSV could not be read: #{error.message}",
      code: :malformed_csv,
      columns: columns,
      rows: rows,
      row_count: row_count
    )
  end

  private

  def append_row(row, columns, row_count, rows, row_limit)
    return row_count unless row

    values = row.fields
    row_count += 1
    rows << { number: row_count, values: values } if row_limit.nil? || rows.length < row_limit
    yield values, row_count
    row_count
  end

  def normalize_limit(limit)
    return if limit.nil?

    value = Integer(limit)
    raise ArgumentError, "The preview row limit must be zero or greater." if value.negative?

    value
  end

  def validate_columns!(columns)
    return unless columns == true || columns.blank?

    raise Error.new("The CSV is empty or does not contain a header row.", code: :missing_header)
  end

  def with_source_io
    if source_file?
      unless @source_file_or_io.file.attached?
        raise Error.new("The source file is not available in local storage.", code: :source_file_unavailable)
      end

      @source_file_or_io.file.open { |io| yield io }
    else
      yield @source_file_or_io
    end
  rescue ActiveStorage::FileNotFoundError, IOError, SystemCallError
    raise Error.new("The source file is not available in local storage.", code: :source_file_unavailable)
  end

  def source_file?
    @source_file_or_io.respond_to?(:file)
  end
end
