defmodule Electric.Postgres.Extension.Migrations.Migration_20230605141256_ElectrifyFunction do
  alias Electric.Postgres.Extension

  @behaviour Extension.Migration

  @impl true
  def version, do: 2023_06_05_14_12_56

  @impl true
  def up(_schema) do
    electrified_tracking_table = Extension.electrified_tracking_table()

    [
      """
      CREATE TABLE #{electrified_tracking_table} (
          id          int8 NOT NULL PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY,
          schema_name text NOT NULL,
          table_name  text NOT NULL,
          oid         oid NOT NULL,
          created_at  timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT unique_table_name UNIQUE (schema_name, table_name)
      )
      """,
      "CREATE INDEX electrified_tracking_table_name_idx ON #{electrified_tracking_table} (schema_name, table_name)",
      "CREATE INDEX electrified_tracking_table_name_oid ON #{electrified_tracking_table} (oid)",
      Extension.add_table_to_publication_sql(electrified_tracking_table)
    ]
  end

  @impl true
  def down(_schema) do
    []
  end
end
