require "metrics_pivotal_tracker/version"
require "metrics_pivotal_tracker/api_helper"
require "tracker_api"
require "rest-client"

module MetricsPivotalTracker
  attr_reader :raw_data

  def initialize(credentials, raw_data=nil)
    @project = credentials[:project]
    @api_token = credentials[:token]
    @client = TrackerApi::Client.new(token: @api_token)
    @raw_data = raw_data
  end

  def image
    return @image if @image
    refresh unless @raw_data
    file_path = File.join(File.dirname(__FILE__), 'svg.erb')
    @image = ERB.new(File.read(file_path)).result(self.send(:binding))
  end

  def refresh
  	project = @client.project(@project)
    lstEstimateAndTime = Array.new
    Delivered = Struct.new(:estimate, :time_delivered)
    project.stories(with_state: :finished||:accepted||:delivered).each do |story|
      if story.estimate
        lstEstimateAndTime << Delivered.new(story.estimate, story.updated_at)
      else
        lstEstimateAndTime << Delivered.new(1, story.updated_at)
      end
    end
    lstEstimateAndTime.sort_by { |x, y| x.time_delivered <=> y.time_delivered }
    time_slide_start = lstEstimateAndTime[0].time_delivered
    tmp_counter = 0
    @countings = Array.new()
    Counting = Struct.new(:starting_time, :velocity)
    lstEstimateAndTime.each do |story|
      if time_exceed? story.time_delivered, time_slide_start
        @countings << Counting.new(time_slide_start, tmp_counter)
        time_slide_start = story.time_delivered
        tmp_counter = 0
      else
        tmp_counter += story.estimate
      end
    end
    @raw_data = {iteration_velocity: @countings}
  end

  def raw_data=(new)
    @raw_data = new
    @score = @image = nil
  end

  def score
    @countings.inject(0.0) { |sum, el| sum + el} / @countings.size
  end

  private
  def api_story_transactions
    response = RestClient.get(get_url("/projects/#{@project}/story_transitions"),
      headers = {X_TrackerToken: @api_token, content_type: :json})
    # NOT SAFE!
    JSON.parse(response.body)
    end
  end

  def get_url(resource)
    "https://www.pivotaltracker.com/services/v5" + resource
  end

  def time_exceed?(time_end, time_start)
    time_limit = 7 * 24 * 60 * 60
    ((time_end - time_start) * 24 * 60 * 60).to_i > time_limit
  end
end
