require "digest"

class SourceFileUploader
  SUPPORTED_CONTENT_TYPES = %w[
    application/csv
    application/octet-stream
    application/vnd.ms-excel
    text/csv
    text/plain
  ].freeze
  CSV_EXTENSION = ".csv"
  READ_BUFFER_SIZE = 64.kilobytes

  class Error < StandardError
  end

  def self.call(dataset:, upload:)
    new(dataset:, upload:).call
  end

  def initialize(dataset:, upload:)
    @dataset = dataset
    @upload = upload
  end

  def call
    validate_upload!

    io = upload_io
    byte_size = upload_size(io)
    raise Error, "The CSV file is empty." if byte_size.zero?

    SourceFileInspector.new(io).call
    sha256 = sha256_for(io)

    source_file = @dataset.source_files.build(
      original_filename: original_filename,
      sha256: sha256,
      byte_size: byte_size
    )
    source_file.file.attach(
      io: io,
      filename: original_filename,
      content_type: normalized_content_type.presence || "text/csv"
    )
    source_file.save!
    source_file
  rescue ActiveRecord::RecordInvalid => error
    raise Error, error.record.errors.full_messages.to_sentence
  rescue SourceFileInspector::Error => error
    raise Error, error.message
  ensure
    io&.rewind
  end

  private

  def validate_upload!
    raise Error, "Choose a CSV file to upload." unless @upload.respond_to?(:original_filename)
    raise Error, "The uploaded file must have a .csv filename." unless csv_filename?
    return if normalized_content_type.blank? || SUPPORTED_CONTENT_TYPES.include?(normalized_content_type)

    raise Error, "This file type is not supported. Upload a CSV file."
  end

  def csv_filename?
    File.extname(original_filename).casecmp(CSV_EXTENSION).zero?
  end

  def upload_io
    io = @upload.respond_to?(:tempfile) ? @upload.tempfile : @upload
    raise Error, "The uploaded file could not be read." unless io.respond_to?(:read) && io.respond_to?(:rewind)

    io
  end

  def upload_size(io)
    return @upload.size.to_i if @upload.respond_to?(:size)
    return io.size.to_i if io.respond_to?(:size)

    raise Error, "The uploaded file size could not be determined."
  end

  def sha256_for(io)
    io.rewind
    digest = Digest::SHA256.new
    while (chunk = io.read(READ_BUFFER_SIZE))
      digest.update(chunk)
    end
    io.rewind
    digest.hexdigest
  end

  def original_filename
    @upload.original_filename.to_s
  end

  def content_type
    @upload.respond_to?(:content_type) ? @upload.content_type.to_s : ""
  end

  def normalized_content_type
    content_type.split(";", 2).first.strip.downcase
  end
end
