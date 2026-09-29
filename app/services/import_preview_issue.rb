class ImportPreviewIssue
  SEVERITIES = %w[error warning info].freeze

  attr_reader :severity, :code, :message, :source_column_name, :source_row_number

  def initialize(severity:, code:, message:, source_column_name: nil, source_row_number: nil)
    @severity = severity.to_s
    raise ArgumentError, "Unsupported preview issue severity." unless SEVERITIES.include?(@severity)

    @code = code.to_s
    @message = message.to_s
    @source_column_name = source_column_name
    @source_row_number = source_row_number
  end

  def error?
    severity == "error"
  end

  def warning?
    severity == "warning"
  end

  def info?
    severity == "info"
  end
end
