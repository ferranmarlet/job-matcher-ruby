module JobscanSchema
  MIGRATIONS = Rails.root.join("db/jobscan_migrations")

  def self.load!
    connection = ActiveRecord::Base.connection
    unless Rails.env.test? && connection.current_database.end_with?("_test")
      raise "Refusing to rebuild #{connection.current_database} in #{Rails.env}: tests must run against a *_test database"
    end

    connection.execute("DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public")
    migrations.each { |path| connection.execute(path.read) }
    connection.schema_cache.clear!
    ActiveRecord::Base.descendants.each(&:reset_column_information)
  end

  def self.migrations
    MIGRATIONS.glob("V*__*.sql").sort_by { |path| Gem::Version.new(path.basename.to_s[/\AV([\d._]+)__/, 1].tr("_", ".")) }
  end
end
