require "rubygems"
require "bundler/setup"
require "sinatra"
require "net/http"
require "uri"
require "json"
require "memcached"

set :port, 1983

get '/' do
  erb :taxi
end

get '/cars' do
  content_type :json

  $cache = Memcached.new("localhost:11211")

  begin
    @cars = $cache.get "cars"
  rescue Memcached::NotFound
    http = Net::HTTP.new("testnambaapi.zapto.org", 8085)
    request = Net::HTTP::Post.new("/SmartServerApi/Api/GetFreeDrivers")
    request.set_form_data({"foo" => "bar"})
    response = http.request(request)
    @cars = JSON.parse(response.body)
    $cache.set "cars", @cars, 60
  end

  @cars["Drivers"].to_json
end
