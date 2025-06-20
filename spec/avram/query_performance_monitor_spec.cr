require "../spec_helper"

describe Avram::QueryPerformanceMonitor do
  describe "QueryMetric" do
    it "identifies slow queries" do
      fast_query = Avram::QueryPerformanceMonitor::QueryMetric.new(
        query: "SELECT * FROM users",
        args: [] of String,
        duration: 50.milliseconds
      )

      slow_query = Avram::QueryPerformanceMonitor::QueryMetric.new(
        query: "SELECT * FROM users",
        args: [] of String,
        duration: 200.milliseconds
      )

      fast_query.slow?.should be_false
      slow_query.slow?.should be_true

      # Test with custom threshold
      fast_query.slow?(25.milliseconds).should be_true
    end

    it "formats duration correctly" do
      micro_query = Avram::QueryPerformanceMonitor::QueryMetric.new(
        query: "SELECT 1",
        args: [] of String,
        duration: 500.microseconds
      )

      milli_query = Avram::QueryPerformanceMonitor::QueryMetric.new(
        query: "SELECT 1",
        args: [] of String,
        duration: 150.milliseconds
      )

      second_query = Avram::QueryPerformanceMonitor::QueryMetric.new(
        query: "SELECT 1",
        args: [] of String,
        duration: 2.5.seconds
      )

      micro_query.to_s.should contain("500.0μs")
      milli_query.to_s.should contain("150.0ms")
      second_query.to_s.should contain("2.5s")
    end
  end

  describe "Monitor" do
    before_each do
      Avram::QueryPerformanceMonitor::Monitor.clear_recorded_queries
      Avram::QueryPerformanceMonitor::Monitor.enabled = true
      Avram::QueryPerformanceMonitor::Monitor.log_all_queries = false
    end

    it "records queries when enabled" do
      result = Avram::QueryPerformanceMonitor::Monitor.record("SELECT * FROM users") do
        42
      end

      result.should eq(42)
      Avram::QueryPerformanceMonitor::Monitor.recorded_queries.size.should eq(1)

      recorded = Avram::QueryPerformanceMonitor::Monitor.recorded_queries.first
      recorded.query.should eq("SELECT * FROM users")
    end

    it "does not record when disabled" do
      Avram::QueryPerformanceMonitor::Monitor.enabled = false

      Avram::QueryPerformanceMonitor::Monitor.record("SELECT * FROM users") do
        42
      end

      Avram::QueryPerformanceMonitor::Monitor.recorded_queries.should be_empty
    end

    it "respects max_recorded_queries limit" do
      Avram::QueryPerformanceMonitor::Monitor.max_recorded_queries = 3

      5.times do |i|
        Avram::QueryPerformanceMonitor::Monitor.record("SELECT #{i}") { nil }
      end

      queries = Avram::QueryPerformanceMonitor::Monitor.recorded_queries
      queries.size.should eq(3)
      queries.map(&.query).should eq(["SELECT 2", "SELECT 3", "SELECT 4"])
    end

    it "identifies slow queries" do
      # Fast query
      Avram::QueryPerformanceMonitor::Monitor.record("SELECT 1") do
        sleep 1.millisecond
      end

      # Slow query
      Avram::QueryPerformanceMonitor::Monitor.handle_metric(
        Avram::QueryPerformanceMonitor::QueryMetric.new(
          query: "SELECT * FROM large_table",
          args: [] of String,
          duration: 200.milliseconds
        )
      )

      slow_queries = Avram::QueryPerformanceMonitor::Monitor.slow_queries
      slow_queries.size.should eq(1)
      slow_queries.first.query.should eq("SELECT * FROM large_table")
    end

    it "generates performance report" do
      io = IO::Memory.new

      # Add some queries
      Avram::QueryPerformanceMonitor::Monitor.handle_metric(
        Avram::QueryPerformanceMonitor::QueryMetric.new(
          query: "SELECT * FROM users",
          args: [] of String,
          duration: 50.milliseconds
        )
      )

      Avram::QueryPerformanceMonitor::Monitor.handle_metric(
        Avram::QueryPerformanceMonitor::QueryMetric.new(
          query: "SELECT * FROM posts WHERE user_id = $1",
          args: ["123"],
          duration: 150.milliseconds
        )
      )

      Avram::QueryPerformanceMonitor::Monitor.report(io)

      report = io.to_s
      report.should contain("Avram Query Performance Report")
      report.should contain("Total queries: 2")
      report.should contain("Slow queries")
      report.should contain("Average query time")
    end
  end

  describe "configuration" do
    it "allows configuration through block" do
      Avram::QueryPerformanceMonitor.configure do |monitor|
        monitor.slow_query_threshold = 50.milliseconds
        monitor.log_all_queries = true
        monitor.max_recorded_queries = 500
      end

      Avram::QueryPerformanceMonitor::Monitor.slow_query_threshold.should eq(50.milliseconds)
      Avram::QueryPerformanceMonitor::Monitor.log_all_queries.should be_true
      Avram::QueryPerformanceMonitor::Monitor.max_recorded_queries.should eq(500)
    end
  end

  describe "integration with query events" do
    it "records queries automatically when logging is initialized" do
      Avram::QueryPerformanceMonitor::Monitor.clear_recorded_queries

      # Simulate a query event
      Avram::Events::QueryEvent.publish(
        query: "SELECT * FROM users WHERE id = $1",
        args: "1",
        queryable: "User"
      ) do
        # Simulate query execution that takes 75ms
        sleep 75.milliseconds
      end

      recorded = Avram::QueryPerformanceMonitor::Monitor.recorded_queries
      recorded.size.should be > 0

      last_query = recorded.last
      last_query.query.should eq("SELECT * FROM users WHERE id = $1")
      last_query.args.should eq(["1"])
    end
  end
end
