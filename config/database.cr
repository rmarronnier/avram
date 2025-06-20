database_name = "avram_dev"

class TestDatabase < Avram::Database
end

class DatabaseWithIncorrectSettings < Avram::Database
end

TestDatabase.configure do |settings|
  settings.credentials = Avram::Credentials.parse?(ENV["DATABASE_URL"]?) || Avram::Credentials.new(
    hostname: ENV["DB_HOST"]? || "localhost",
    database: database_name,
    username: ENV["DB_USERNAME"]? || "lucky",
    password: ENV["DB_PASSWORD"]? || "developer",
    port: (ENV["DB_PORT"]? || "5432").to_i
  )
end

class SampleBackupDatabase < Avram::Database
end

SampleBackupDatabase.configure do |settings|
  settings.credentials = Avram::Credentials.parse?(ENV["BACKUP_DATABASE_URL"]?) || Avram::Credentials.new(
    hostname: ENV["DB_HOST"]? || "localhost",
    database: "sample_backup",
    username: ENV["DB_USERNAME"]? || "lucky",
    password: ENV["DB_PASSWORD"]? || "developer",
    port: (ENV["DB_PORT"]? || "5432").to_i
  )
end

DatabaseWithIncorrectSettings.configure do |settings|
  settings.credentials = Avram::Credentials.new(
    hostname: ENV["DB_HOST"]? || "localhost",
    database: database_name,
    username: "incorrect",
    port: (ENV["DB_PORT"]? || "5432").to_i
  )
end

Avram.configure do |settings|
  settings.database_to_migrate = TestDatabase
end
