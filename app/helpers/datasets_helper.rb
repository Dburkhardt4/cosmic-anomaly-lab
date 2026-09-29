module DatasetsHelper
  def safe_external_url(value)
    return if value.blank?

    uri = URI.parse(value)
    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
end
