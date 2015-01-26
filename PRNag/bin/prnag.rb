require 'httparty'
require 'optparse'
require 'yaml'

config = YAML.load_file('config.yml')
@owner = config['config']['owner']
@repo = config['config']['repo']
@expire_range = config['config']['expire_range']

class PRClient
	include HTTParty

	GITHUB_URI = 'https://api.github.com'

	base_uri GITHUB_URI
	headers 'Accept' => 'application/json', 'Content-Type' => 'application/json'
	format :json

	def initialize(token, userAgent)
		raise "Please supply a token" if token.nil?
		@token = token
		self.class.headers 'Authorization' => "token #{token}", 'User-Agent' => "#{userAgent}"

		test_connection
	end

	def get_pulls(owner, repo)
		response = self.class.get "/repos/#{owner}/#{repo}/pulls"
	end

	def get_single_pull(owner, repo, number)
		response = self.class.get "/repos/#{owner}/#{repo}/pulls/#{number}"
	end

	def post_comment(owner, repo, number, comment)
		options = { :body => { "body" => "#{comment}" }.to_json }
		response = self.class.post("/repos/#{owner}/#{repo}/issues/#{number}/comments", options)
		return response
	end

	private
		def test_connection
			response = self.class.get '/user'
			raise "Bad connection, got this response code: #{response.code}" if response.code != 200			
		end
end

options = {
	token: nil,
}

parser = OptionParser.new do |opts|
	opts.banner = "Usage: pr_bot.rb [options]"

	opts.on('-t', '--token token', 'Your OAuth token') do |token|
		options[:token] = token
	end
end

parser.parse!

if options.values.all?(&:nil?)
	puts parser.to_s
	exit
end

@client = PRClient.new(options[:token], @owner)

#calc the days
def pr_age(today, created)
	today.mjd - created.mjd
end

#get all PR's that are older than the config expired range setting
def get_stale_pulls
	today_time = DateTime.now

	pulls = @client.get_pulls(@owner, @repo)
	old_pr_numbers = []
	pulls.each do |pull|
		if pr_age(today_time, DateTime.iso8601(pull['created_at'])) >= @expire_range
			old_pr_numbers.push(pull['number'])
		end
	end
	return old_pr_numbers
end

#get the create and update dates to calc days old and last updated days. Use these to generate comment details
def generate_comment(number)
	today_time = DateTime.now

	single_pull = @client.get_single_pull(@owner, @repo, number)
	created_at = single_pull['created_at']
	updated_at = single_pull['updated_at']

	days_old = pr_age(today_time, DateTime.iso8601(created_at))

	updated_since = pr_age(today_time, DateTime.iso8601(updated_at))

	return "Your PR was opened #{days_old} days ago and has not been updated in #{updated_since} days. Please merge or close this PR."
end

#post to each stale branch with comment that reminds the owner on how long it has be open, the last time it was updated and to do something with PR.
prs = get_stale_pulls

prs.each do |number|
	comment_body = generate_comment(number)
	@client.post_comment(@owner, @repo, number, comment_body)
end



