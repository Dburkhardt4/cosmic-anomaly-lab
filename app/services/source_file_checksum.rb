require "digest"

class SourceFileChecksum
  READ_BUFFER_SIZE = 64.kilobytes

  class Error < StandardError
  end

  def self.for_io(io)
    new.for_io(io)
  end

  def self.for_source_file(source_file)
    new.for_source_file(source_file)
  end

  def for_io(io)
    raise Error, "The source file could not be read." unless io.respond_to?(:read) && io.respond_to?(:rewind)

    io.rewind
    digest = Digest::SHA256.new
    byte_size = 0

    while (chunk = io.read(READ_BUFFER_SIZE))
      digest.update(chunk)
      byte_size += chunk.bytesize
    end

    { sha256: digest.hexdigest, byte_size: byte_size }
  rescue IOError, SystemCallError => error
    raise Error, "The source file could not be read: #{error.message}"
  ensure
    io&.rewind
  end

  def for_source_file(source_file)
    unless source_file.file.attached?
      raise Error, "The source file is not available in local storage."
    end

    source_file.file.open { |io| for_io(io) }
  rescue ActiveStorage::FileNotFoundError, IOError, SystemCallError
    raise Error, "The source file is not available in local storage."
  end
end
