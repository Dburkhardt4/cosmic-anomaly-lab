# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

[
  {
    key: "right_ascension",
    name: "Right Ascension",
    description: "An angular coordinate used to describe position on the sky.",
    expected_value_type: "number",
    canonical_unit: "degree",
    notes: "The source column's coordinate convention and units must be reviewed separately."
  },
  {
    key: "declination",
    name: "Declination",
    description: "An angular coordinate used to describe position north or south of the celestial equator.",
    expected_value_type: "number",
    canonical_unit: "degree",
    notes: "The source column's coordinate convention and units must be reviewed separately."
  },
  {
    key: "observation_time",
    name: "Observation Time",
    description: "A time associated with an observation or measurement.",
    expected_value_type: "datetime",
    canonical_unit: nil,
    notes: "The source timestamp format and time scale must be reviewed separately."
  }
].each do |attributes|
  NormalizedConcept.find_or_initialize_by(key: attributes[:key]).update!(attributes)
end
