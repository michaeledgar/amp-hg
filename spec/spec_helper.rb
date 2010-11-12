$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rubygems'
require 'amp-front'
require 'amp-core'
require 'amp-hg'
require 'spec'
require 'spec/autorun'
require 'construct'

Spec::Runner.configure do |config|
  
end
