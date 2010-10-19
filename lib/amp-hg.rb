class Amp::Plugins::Hg < Amp::Plugins::Base
  def initialize(opts)
    @opts = opts
  end
  
  def load!
    puts "Loading amp-hg..."
  end
end