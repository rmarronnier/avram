module Avram::QueryPerformanceMonitor
  class QueryMetric
    getter query : String
    getter args : Array(String)
    getter duration : Time::Span
    getter rows_affected : Int64?
    getter caller_location : String?
    getter timestamp : Time

    def initialize(@query : String, @args : Array(String), @duration : Time::Span,
                   @rows_affected : Int64? = nil, @caller_location : String? = nil)
      @timestamp = Time.utc
    end

    def slow?(threshold : Time::Span = 100.milliseconds) : Bool
      @duration > threshold
    end

    def to_s(io : IO) : Nil
      io << "[#{@timestamp.to_s("%Y-%m-%d %H:%M:%S")}] "
      io << "Query took #{formatted_duration}"
      io << " (#{@rows_affected} rows)" if @rows_affected
      io << "\n"
      io << "  SQL: #{@query}\n"
      io << "  Args: #{@args.inspect}\n" unless @args.empty?
      io << "  Called from: #{@caller_location}\n" if @caller_location
    end

    private def formatted_duration : String
      case
      when @duration >= 1.second
        "#{@duration.total_seconds.round(2)}s"
      when @duration >= 1.millisecond
        "#{@duration.total_milliseconds.round(2)}ms"
      else
        "#{@duration.total_microseconds.round(2)}μs"
      end
    end
  end

  class Monitor
    class_property slow_query_threshold : Time::Span = 100.milliseconds
    class_property log_all_queries : Bool = false
    class_property enabled : Bool = true
    class_property query_logger : IO = STDOUT
    class_property max_recorded_queries : Int32 = 1000

    @@recorded_queries = [] of QueryMetric
    @@mutex = Mutex.new

    def self.record(query : String, args : Array(String) = [] of String, &block)
      return yield unless enabled

      start_time = Time.monotonic
      result = yield
      end_time = Time.monotonic

      duration = end_time - start_time
      caller_location = get_caller_location

      metric = QueryMetric.new(
        query: query,
        args: args,
        duration: duration,
        caller_location: caller_location
      )

      handle_metric(metric)

      result
    end

    def self.handle_metric(metric : QueryMetric)
      @@mutex.synchronize do
        # Store metric
        @@recorded_queries << metric
        if @@recorded_queries.size > max_recorded_queries
          @@recorded_queries.shift
        end

        # Log if necessary
        if log_all_queries || metric.slow?(slow_query_threshold)
          log_query(metric)
        end
      end
    end

    def self.log_query(metric : QueryMetric)
      query_logger.puts("\n[AVRAM QUERY #{metric.slow? ? "SLOW" : "LOG"}]")
      query_logger.puts(metric.to_s)
      query_logger.flush
    end

    def self.recorded_queries : Array(QueryMetric)
      @@mutex.synchronize { @@recorded_queries.dup }
    end

    def self.slow_queries(threshold : Time::Span = slow_query_threshold) : Array(QueryMetric)
      recorded_queries.select { |q| q.slow?(threshold) }
    end

    def self.clear_recorded_queries
      @@mutex.synchronize { @@recorded_queries.clear }
    end

    def self.report(io : IO = STDOUT)
      queries = recorded_queries
      return if queries.empty?

      io.puts("\n=== Avram Query Performance Report ===")
      io.puts("Total queries: #{queries.size}")

      slow = slow_queries
      if slow.any?
        io.puts("\nSlow queries (> #{slow_query_threshold.total_milliseconds}ms): #{slow.size}")
        slow.each_with_index do |query, index|
          io.puts("\n#{index + 1}. #{query}")
        end
      end

      # Top 10 slowest queries
      top_slow = queries.sort_by(&.duration).reverse.first(10)
      io.puts("\n\nTop 10 slowest queries:")
      top_slow.each_with_index do |query, index|
        io.puts("\n#{index + 1}. Duration: #{query.duration.total_milliseconds}ms")
        io.puts("   SQL: #{query.query.lines.first}")
      end

      # Average query time
      avg_duration = queries.sum(&.duration) / queries.size
      io.puts("\n\nAverage query time: #{avg_duration.total_milliseconds.round(2)}ms")

      io.flush
    end

    private def self.get_caller_location : String?
      # Skip frames to get the actual calling location
      backtrace = caller
      relevant_frame = backtrace.find do |frame|
        !frame.includes?("/avram/") && !frame.includes?("/crystal/")
      end
      
      relevant_frame
    rescue
      nil
    end
  end

  # Configuration helper
  def self.configure(&block)
    yield Monitor
  end
end
