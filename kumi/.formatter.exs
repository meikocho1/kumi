[
  import_deps: [:ash, :ash_postgres, :ecto, :ecto_sql],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
