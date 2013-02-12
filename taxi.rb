require "rubygems"
require "bundler/setup"
require "sinatra"

get '/' do
  erb :taxi
end