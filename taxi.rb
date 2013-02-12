require "rubygems"
require "bundler/setup"
require "sinatra"

set :port, 1983

get '/' do
  erb :taxi
end