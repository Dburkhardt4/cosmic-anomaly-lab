class DatasetComparison
  SAMPLE_LIMIT = 3

  def self.call(dataset_a:, dataset_b:)
    new(dataset_a: dataset_a, dataset_b: dataset_b).call
  end

  def initialize(dataset_a:, dataset_b:)
    @dataset_a = dataset_a
    @dataset_b = dataset_b
    @dataset_ids = [ @dataset_a.id, @dataset_b.id ]
  end

  def call
    presence_by_dataset = concept_presence_by_dataset
    concepts_by_key = load_concepts(presence_by_dataset)
    record_counts = record_counts_by_dataset
    source_file_counts = source_file_counts_by_dataset
    record_types = record_types_by_dataset
    samples_by_dataset = sample_values_by_dataset

    dataset_a_concepts = concept_summaries(@dataset_a.id, presence_by_dataset[@dataset_a.id], concepts_by_key, samples_by_dataset)
    dataset_b_concepts = concept_summaries(@dataset_b.id, presence_by_dataset[@dataset_b.id], concepts_by_key, samples_by_dataset)
    dataset_a_keys = dataset_a_concepts.to_h { |concept| [ concept[:key], concept ] }
    dataset_b_keys = dataset_b_concepts.to_h { |concept| [ concept[:key], concept ] }
    shared_keys = dataset_a_keys.keys & dataset_b_keys.keys

    {
      dataset_a: dataset_summary(@dataset_a, record_counts, source_file_counts, record_types, dataset_a_concepts),
      dataset_b: dataset_summary(@dataset_b, record_counts, source_file_counts, record_types, dataset_b_concepts),
      shared_concepts: shared_keys.map do |key|
        dataset_a_keys[key].merge(
          dataset_a_record_count: dataset_a_keys[key][:record_count],
          dataset_b_record_count: dataset_b_keys[key][:record_count],
          dataset_a_samples: dataset_a_keys[key][:samples],
          dataset_b_samples: dataset_b_keys[key][:samples]
        )
      end.sort_by { |concept| concept[:name].to_s },
      dataset_a_only: (dataset_a_keys.keys - shared_keys).filter_map { |key| dataset_a_keys[key] }
        .sort_by { |concept| concept[:name].to_s },
      dataset_b_only: (dataset_b_keys.keys - shared_keys).filter_map { |key| dataset_b_keys[key] }
        .sort_by { |concept| concept[:name].to_s },
      readiness: readiness(
        shared_keys: shared_keys,
        dataset_a_record_count: record_counts.fetch(@dataset_a.id, 0),
        dataset_b_record_count: record_counts.fetch(@dataset_b.id, 0),
        dataset_a_concepts: dataset_a_keys,
        dataset_b_concepts: dataset_b_keys
      )
    }
  end

  private

  def concept_presence_by_dataset
    presence = @dataset_ids.to_h { |dataset_id| [ dataset_id, {} ] }

    mapping_rows.each do |row|
      add_concept_presence(
        presence.fetch(row.fetch("dataset_id").to_i),
        key: row.fetch("concept_key"),
        name: row["concept_name"],
        source_column_name: row["source_column_name"]
      )
    end

    normalized_value_rows.each do |row|
      entry = add_concept_presence(
        presence.fetch(row.fetch("dataset_id").to_i),
        key: row["concept_key"],
        name: row["concept_name"]
      )
      entry[:record_count] = [ entry[:record_count], row.fetch("record_count").to_i ].max
    end

    presence
  end

  def add_concept_presence(dataset_presence, key:, name:, source_column_name: nil)
    return {} if key.blank?

    entry = dataset_presence[key] ||= {
      key: key,
      name: name,
      source_columns: [],
      record_count: 0
    }
    entry[:name] ||= name
    entry[:source_columns] << source_column_name if source_column_name.present? && !entry[:source_columns].include?(source_column_name)
    entry
  end

  def load_concepts(presence_by_dataset)
    keys = presence_by_dataset.values.flat_map(&:keys).uniq
    NormalizedConcept.where(key: keys).index_by(&:key)
  end

  def concept_summaries(dataset_id, dataset_presence, concepts_by_key, samples_by_dataset)
    dataset_presence.values.map do |presence|
      concept = concepts_by_key[presence[:key]]
      {
        key: presence[:key],
        name: concept&.name || presence[:name] || presence[:key],
        canonical_unit: concept&.canonical_unit,
        expected_value_type: concept&.expected_value_type,
        source_columns: presence[:source_columns],
        record_count: presence[:record_count],
        samples: samples_by_dataset.dig(dataset_id, presence[:key]) || []
      }
    end
  end

  def dataset_summary(dataset, record_counts, source_file_counts, record_types, concepts)
    {
      dataset: dataset,
      record_count: record_counts.fetch(dataset.id, 0),
      source_file_count: source_file_counts.fetch(dataset.id, 0),
      record_types: record_types.fetch(dataset.id, []).sort,
      concepts: concepts
    }
  end

  def readiness(shared_keys:, dataset_a_record_count:, dataset_b_record_count:, dataset_a_concepts:, dataset_b_concepts:)
    if shared_keys.empty?
      {
        status: :none,
        title: "No shared normalized concepts",
        detail: "These datasets currently expose no common concepts through explicit mappings or persisted normalized values."
      }
    elsif dataset_a_record_count.zero? || dataset_b_record_count.zero?
      {
        status: :no_records,
        title: "Imported records are required",
        detail: "Shared concepts are present, but both datasets need imported records before coverage can be assessed."
      }
    elsif shared_keys.any? do |key|
      dataset_a_concepts.fetch(key).fetch(:record_count) < dataset_a_record_count ||
        dataset_b_concepts.fetch(key).fetch(:record_count) < dataset_b_record_count
    end
      {
        status: :partial,
        title: "Shared concepts found with partial record coverage",
        detail: "The shared concepts are available for structural comparison, but at least one shared concept is absent from some imported records."
      }
    else
      {
        status: :shared,
        title: "Shared normalized concepts found",
        detail: "The selected datasets expose common explicitly mapped concepts across their imported records."
      }
    end
  end

  def record_counts_by_dataset
    normalized_records_scope.group("source_files.dataset_id").count
  end

  def source_file_counts_by_dataset
    SourceFile.where(dataset_id: @dataset_ids).group(:dataset_id).count
  end

  def record_types_by_dataset
    normalized_records_scope.group("source_files.dataset_id", :record_type).count
      .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((dataset_id, record_type), _count), result|
        result[dataset_id] << record_type
      end
  end

  def normalized_records_scope
    NormalizedRecord.joins(imported_source_record: :source_file)
      .where(source_files: { dataset_id: @dataset_ids })
  end

  def mapping_rows
    FieldMapping.joins(:source_file, :normalized_concept)
      .where(source_files: { dataset_id: @dataset_ids }, status: FieldMapping.statuses.fetch("mapped"))
      .pluck(
        "source_files.dataset_id",
        "normalized_concepts.key",
        "normalized_concepts.name",
        "field_mappings.source_column_name"
      ).map do |dataset_id, concept_key, concept_name, source_column_name|
        {
          "dataset_id" => dataset_id,
          "concept_key" => concept_key,
          "concept_name" => concept_name,
          "source_column_name" => source_column_name
        }
      end
  end

  def normalized_value_rows
    sql = ActiveRecord::Base.sanitize_sql_array([
      <<~SQL,
        SELECT source_files.dataset_id,
               json_extract(normalized_value.value, '$.concept_key') AS concept_key,
               COUNT(DISTINCT normalized_records.id) AS record_count
        FROM normalized_records
        INNER JOIN imported_source_records
          ON imported_source_records.id = normalized_records.imported_source_record_id
        INNER JOIN source_files
          ON source_files.id = imported_source_records.source_file_id
        JOIN json_each(normalized_records.normalized_values) AS normalized_value
        WHERE source_files.dataset_id IN (?, ?)
          AND imported_source_records.status = 'accepted'
        GROUP BY source_files.dataset_id, concept_key
      SQL
      *@dataset_ids
    ])

    ApplicationRecord.connection.select_all(sql).to_a
  end

  def sample_values_by_dataset
    sql = ActiveRecord::Base.sanitize_sql_array([
      <<~SQL,
        SELECT dataset_id, concept_key, stored_value
        FROM (
          SELECT source_files.dataset_id AS dataset_id,
                 json_extract(normalized_value.value, '$.concept_key') AS concept_key,
                 json_extract(normalized_value.value, '$.value') AS stored_value,
                 ROW_NUMBER() OVER (
                   PARTITION BY source_files.dataset_id, json_extract(normalized_value.value, '$.concept_key')
                   ORDER BY normalized_records.id
                 ) AS sample_rank
          FROM normalized_records
          INNER JOIN imported_source_records
            ON imported_source_records.id = normalized_records.imported_source_record_id
          INNER JOIN source_files
            ON source_files.id = imported_source_records.source_file_id
          JOIN json_each(normalized_records.normalized_values) AS normalized_value
          WHERE source_files.dataset_id IN (?, ?)
            AND imported_source_records.status = 'accepted'
        )
        WHERE sample_rank <= #{SAMPLE_LIMIT}
      SQL
      *@dataset_ids
    ])

    ApplicationRecord.connection.select_all(sql).to_a.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new { |nested, nested_key| nested[nested_key] = [] } }) do |row, result|
      result[row.fetch("dataset_id").to_i][row["concept_key"]] << row["stored_value"]
    end
  end
end
